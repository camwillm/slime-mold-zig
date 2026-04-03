// Phase 1 (sim loop): peristaltic phase advance + D_eff computation
// Phase 3 (sim loop): Poiseuille flow calculation
// Phase 4 (sim loop): Tero conductance adaptation with softening boost

const std     = @import("std");
const net_mod = @import("network.zig");
const Network = net_mod.Network;

// Phase 1 (doc 08): advance phases uniformly, compute D_eff for active edges only.
// Kuramoto coupling removed (O(n²) neighbor scan, too expensive at 79k edges).
// Uniform advance still produces the traveling wave visual.
pub fn advancePhases(net: *Network) void {
    const w   = net.width;
    const h   = net.height;
    const tau = std.math.tau;
    const dt  = net_mod.OMEGA * net_mod.DT;

    for (0..h) |y| {
        for (0..w - 1) |x| {
            const e = net.horizEdgeIndex(x, y);
            if (net.active[e] == 0) continue;

            net.phase[e] += dt;
            if (net.phase[e] >= tau) net.phase[e] -= tau;

            const ni      = y * w + x;
            const nj      = y * w + (x + 1);
            const sig_avg = (net.signal[ni] + net.signal[nj]) * 0.5;
            const a_eff   = net_mod.AMPLITUDE + net_mod.SIGNAL_COUPLING * sig_avg;
            var deff = net.conductance[e] * (1.0 + a_eff * @sin(net.phase[e]));
            if (deff < net_mod.MIN_CONDUCTANCE) deff = net_mod.MIN_CONDUCTANCE;
            net.d_eff[e] = deff;
        }
    }

    for (0..h - 1) |y| {
        for (0..w) |x| {
            const e = net.vertEdgeIndex(x, y);
            if (net.active[e] == 0) continue;

            net.phase[e] += dt;
            if (net.phase[e] >= tau) net.phase[e] -= tau;

            const ni      = y * w + x;
            const nj      = (y + 1) * w + x;
            const sig_avg = (net.signal[ni] + net.signal[nj]) * 0.5;
            const a_eff   = net_mod.AMPLITUDE + net_mod.SIGNAL_COUPLING * sig_avg;
            var deff = net.conductance[e] * (1.0 + a_eff * @sin(net.phase[e]));
            if (deff < net_mod.MIN_CONDUCTANCE) deff = net_mod.MIN_CONDUCTANCE;
            net.d_eff[e] = deff;
        }
    }
}

// Phase 3 (doc 08): Q_ij = D_eff_ij * (P_i - P_j)
pub fn calcFlow(net: *Network) void {
    const w = net.width;
    const h = net.height;

    for (0..h) |y| {
        for (0..w - 1) |x| {
            const e = net.horizEdgeIndex(x, y);
            if (net.active[e] == 0) { net.flow[e] = 0.0; continue; }
            net.flow[e] = net.d_eff[e] * (net.pressure[y * w + x] - net.pressure[y * w + (x + 1)]);
        }
    }

    for (0..h - 1) |y| {
        for (0..w) |x| {
            const e = net.vertEdgeIndex(x, y);
            if (net.active[e] == 0) { net.flow[e] = 0.0; continue; }
            net.flow[e] = net.d_eff[e] * (net.pressure[y * w + x] - net.pressure[(y + 1) * w + x]);
        }
    }
}

// Phase 4 (doc 08): dD/dt = |Q| + alpha*softening_avg - gamma*D  (Tero + softening boost)
pub fn updateConductance(net: *Network) void {
    const w = net.width;
    const h = net.height;

    for (0..h) |y| {
        for (0..w - 1) |x| {
            const e  = net.horizEdgeIndex(x, y);
            const ni = y * w + x;
            const nj = y * w + (x + 1);
            updateEdge(net, e, ni, nj);
        }
    }

    for (0..h - 1) |y| {
        for (0..w) |x| {
            const e  = net.vertEdgeIndex(x, y);
            const ni = y * w + x;
            const nj = (y + 1) * w + x;
            updateEdge(net, e, ni, nj);
        }
    }
}

inline fn updateEdge(net: *Network, e: usize, ni: usize, nj: usize) void {
    // Spiderweb model: dead edges don't update. Only frontier expansion reactivates edges.
    if (net.active[e] == 0) return;

    const q              = @abs(net.flow[e]);
    const softening_avg  = (net.softening[ni] + net.softening[nj]) * 0.5;
    const gradient_avg   = (net.food_gradient[ni] + net.food_gradient[nj]) * 0.5;
    const gradient_boost = net_mod.GRADIENT_WEIGHT * gradient_avg / 255.0;
    const dD             = net_mod.DT * (q + gradient_boost + net_mod.SOFTENING_WEIGHT * softening_avg - net_mod.DECAY * net.conductance[e]);
    net.conductance[e]  += dD;

    if (net.conductance[e] < net_mod.MIN_CONDUCTANCE) {
        net.conductance[e] = 0.0;
        net.active[e]      = 0;
    } else if (net.conductance[e] > net_mod.MAX_CONDUCTANCE) {
        net.conductance[e] = net_mod.MAX_CONDUCTANCE;
    }
}

// Xorshift32 for expand conductance jitter (no allocator needed in WASM).
var expand_rng: u32 = 99991;
inline fn xorshift32(s: *u32) f32 {
    s.* ^= s.* << 13;
    s.* ^= s.* >> 17;
    s.* ^= s.* << 5;
    return @as(f32, @floatFromInt(s.* & 0xFFFF)) / 65536.0;
}

// Spiderweb frontier expansion (called every 10 ticks from main.zig).
// For every node on the active frontier, try to activate each inactive neighbor edge
// if the food gradient at that location exceeds EXPAND_THRESHOLD.
pub fn expandFrontier(net: *Network) void {
    const EXPAND_THRESHOLD:   f32 = 0.5;
    const EXPAND_CONDUCTANCE: f32 = 0.008;

    const w = net.width;
    const h = net.height;

    // Build active node set.
    var active_nodes = [_]bool{false} ** net_mod.TOTAL_NODES;
    for (0..h) |y| {
        for (0..w - 1) |x| {
            const e = net.horizEdgeIndex(x, y);
            if (net.active[e] != 0) {
                active_nodes[y * w + x]       = true;
                active_nodes[y * w + (x + 1)] = true;
            }
        }
    }
    for (0..h - 1) |y| {
        for (0..w) |x| {
            const e = net.vertEdgeIndex(x, y);
            if (net.active[e] != 0) {
                active_nodes[y * w + x]       = true;
                active_nodes[(y + 1) * w + x] = true;
            }
        }
    }

    for (0..h) |y| {
        for (0..w) |x| {
            const i = y * w + x;
            if (!active_nodes[i])          continue;
            if (net.is_boundary[i] != 0)   continue;

            // Right
            if (x < w - 1 and net.is_boundary[y * w + (x + 1)] == 0) {
                const e = net.horizEdgeIndex(x, y);
                if (net.active[e] == 0) {
                    const j    = y * w + (x + 1);
                    const grad = (net.food_gradient[i] + net.food_gradient[j]) * 0.5;
                    if (grad > EXPAND_THRESHOLD) {
                        net.active[e]      = 1;
                        net.conductance[e] = EXPAND_CONDUCTANCE + xorshift32(&expand_rng) * 0.002;
                        net.d_eff[e]       = net.conductance[e];
                    }
                }
            }
            // Left
            if (x > 0 and net.is_boundary[y * w + (x - 1)] == 0) {
                const e = net.horizEdgeIndex(x - 1, y);
                if (net.active[e] == 0) {
                    const j    = y * w + (x - 1);
                    const grad = (net.food_gradient[i] + net.food_gradient[j]) * 0.5;
                    if (grad > EXPAND_THRESHOLD) {
                        net.active[e]      = 1;
                        net.conductance[e] = EXPAND_CONDUCTANCE + xorshift32(&expand_rng) * 0.002;
                        net.d_eff[e]       = net.conductance[e];
                    }
                }
            }
            // Down (y+1)
            if (y < h - 1 and net.is_boundary[(y + 1) * w + x] == 0) {
                const e = net.vertEdgeIndex(x, y);
                if (net.active[e] == 0) {
                    const j    = (y + 1) * w + x;
                    const grad = (net.food_gradient[i] + net.food_gradient[j]) * 0.5;
                    if (grad > EXPAND_THRESHOLD) {
                        net.active[e]      = 1;
                        net.conductance[e] = EXPAND_CONDUCTANCE + xorshift32(&expand_rng) * 0.002;
                        net.d_eff[e]       = net.conductance[e];
                    }
                }
            }
            // Up (y-1)
            if (y > 0 and net.is_boundary[(y - 1) * w + x] == 0) {
                const e = net.vertEdgeIndex(x, y - 1);
                if (net.active[e] == 0) {
                    const j    = (y - 1) * w + x;
                    const grad = (net.food_gradient[i] + net.food_gradient[j]) * 0.5;
                    if (grad > EXPAND_THRESHOLD) {
                        net.active[e]      = 1;
                        net.conductance[e] = EXPAND_CONDUCTANCE + xorshift32(&expand_rng) * 0.002;
                        net.d_eff[e]       = net.conductance[e];
                    }
                }
            }
        }
    }
}

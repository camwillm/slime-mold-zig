// Phase 1 (sim loop): peristaltic phase advance + D_eff computation
// Phase 3 (sim loop): Poiseuille flow calculation
// Phase 4 (sim loop): Tero conductance adaptation with softening boost

const std     = @import("std");
const net_mod = @import("network.zig");
const Network = net_mod.Network;

// Phase 1 (doc 08): advance phases via Kuramoto coupling, compute D_eff.
// Must run before pressure solve so solver uses current D_eff.
pub fn advancePhases(net: *Network) void {
    const w   = net.width;
    const h   = net.height;
    const tau = std.math.tau;

    // --- Horizontal edges: between (x,y) and (x+1,y) ---
    for (0..h) |y| {
        for (0..w - 1) |x| {
            const e = net.horizEdgeIndex(x, y);
            if (net.active[e] == 0) {
                net.d_eff[e] = net_mod.MIN_CONDUCTANCE;
                continue;
            }

            // Kuramoto coupling: sum sin(φ_neighbor - φ_e) over all edges sharing a node
            var coupling: f32 = 0.0;

            // Left node (x, y) neighbors
            if (x > 0)     coupling += @sin(net.phase[net.horizEdgeIndex(x - 1, y)]     - net.phase[e]);
            if (y > 0)     coupling += @sin(net.phase[net.vertEdgeIndex(x,     y - 1)]  - net.phase[e]);
            if (y < h - 1) coupling += @sin(net.phase[net.vertEdgeIndex(x,     y)]      - net.phase[e]);

            // Right node (x+1, y) neighbors
            if (x < w - 2) coupling += @sin(net.phase[net.horizEdgeIndex(x + 1, y)]     - net.phase[e]);
            if (y > 0)     coupling += @sin(net.phase[net.vertEdgeIndex(x + 1, y - 1)]  - net.phase[e]);
            if (y < h - 1) coupling += @sin(net.phase[net.vertEdgeIndex(x + 1, y)]      - net.phase[e]);

            net.phase[e] += net_mod.K * net_mod.DT * coupling;
            net.phase[e] += net_mod.OMEGA * net_mod.DT;
            if (net.phase[e] >= tau) net.phase[e] -= tau;
            if (net.phase[e] < 0.0)  net.phase[e] += tau;

            const ni      = y * w + x;
            const nj      = y * w + (x + 1);
            const sig_avg = (net.signal[ni] + net.signal[nj]) * 0.5;
            const a_eff   = net_mod.AMPLITUDE + net_mod.SIGNAL_COUPLING * sig_avg;
            var deff = net.conductance[e] * (1.0 + a_eff * @sin(net.phase[e]));
            if (deff < net_mod.MIN_CONDUCTANCE) deff = net_mod.MIN_CONDUCTANCE;
            net.d_eff[e] = deff;
        }
    }

    // --- Vertical edges: between (x,y) and (x,y+1) ---
    for (0..h - 1) |y| {
        for (0..w) |x| {
            const e = net.vertEdgeIndex(x, y);
            if (net.active[e] == 0) {
                net.d_eff[e] = net_mod.MIN_CONDUCTANCE;
                continue;
            }

            var coupling: f32 = 0.0;

            // Top node (x, y) neighbors
            if (x > 0)     coupling += @sin(net.phase[net.horizEdgeIndex(x - 1, y)]     - net.phase[e]);
            if (x < w - 1) coupling += @sin(net.phase[net.horizEdgeIndex(x,     y)]     - net.phase[e]);
            if (y > 0)     coupling += @sin(net.phase[net.vertEdgeIndex(x,     y - 1)]  - net.phase[e]);

            // Bottom node (x, y+1) neighbors
            if (x > 0)     coupling += @sin(net.phase[net.horizEdgeIndex(x - 1, y + 1)] - net.phase[e]);
            if (x < w - 1) coupling += @sin(net.phase[net.horizEdgeIndex(x,     y + 1)] - net.phase[e]);
            if (y < h - 2) coupling += @sin(net.phase[net.vertEdgeIndex(x,     y + 1)]  - net.phase[e]);

            net.phase[e] += net_mod.K * net_mod.DT * coupling;
            net.phase[e] += net_mod.OMEGA * net_mod.DT;
            if (net.phase[e] >= tau) net.phase[e] -= tau;
            if (net.phase[e] < 0.0)  net.phase[e] += tau;

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
    const q              = @abs(net.flow[e]);
    const softening_avg  = (net.softening[ni] + net.softening[nj]) * 0.5;
    const dD             = net_mod.DT * (q + net_mod.SOFTENING_WEIGHT * softening_avg - net_mod.DECAY * net.conductance[e]);
    net.conductance[e]  += dD;

    if (net.conductance[e] < net_mod.MIN_CONDUCTANCE) {
        net.conductance[e] = net_mod.MIN_CONDUCTANCE;
        net.active[e]      = 0;
    } else if (net.conductance[e] > net_mod.MAX_CONDUCTANCE) {
        net.conductance[e] = net_mod.MAX_CONDUCTANCE;
    }

    if (net.active[e] == 0 and net.conductance[e] > net_mod.REACTIVATION_THRESHOLD) {
        net.active[e] = 1;
    }
}

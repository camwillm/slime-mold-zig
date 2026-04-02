// Phases 5-7 of the simulation loop (doc 08):
//   Phase 5: cAMP signal advection + diffusion + production + decay   (Alim 2017)
//   Phase 6: softening agent advection + diffusion + decay            (Kramar & Alim 2021)
//   Phase 7: food consumption → softening burst on depletion

const net_mod = @import("network.zig");
const Network = net_mod.Network;

// Phase 5: upwind advection, sum-form diffusion, production at food nodes, decay.
pub fn advectSignal(net: *Network) void {
    const w = net.width;
    const h = net.height;

    // Upwind advection — horizontal edges
    for (0..h) |y| {
        for (0..w - 1) |x| {
            const e = net.horizEdgeIndex(x, y);
            if (net.active[e] == 0) continue;
            const q  = net.flow[e];
            const ni = y * w + x;
            const nj = y * w + (x + 1);
            if (q > 0.0) {
                var t = net_mod.DT * q * net.signal[ni];
                if (t > net.signal[ni]) t = net.signal[ni];
                net.signal[ni] -= t;
                net.signal[nj] += t;
            } else if (q < 0.0) {
                var t = net_mod.DT * (-q) * net.signal[nj];
                if (t > net.signal[nj]) t = net.signal[nj];
                net.signal[nj] -= t;
                net.signal[ni] += t;
            }
        }
    }

    // Upwind advection — vertical edges
    for (0..h - 1) |y| {
        for (0..w) |x| {
            const e = net.vertEdgeIndex(x, y);
            if (net.active[e] == 0) continue;
            const q  = net.flow[e];
            const ni = y * w + x;
            const nj = (y + 1) * w + x;
            if (q > 0.0) {
                var t = net_mod.DT * q * net.signal[ni];
                if (t > net.signal[ni]) t = net.signal[ni];
                net.signal[ni] -= t;
                net.signal[nj] += t;
            } else if (q < 0.0) {
                var t = net_mod.DT * (-q) * net.signal[nj];
                if (t > net.signal[nj]) t = net.signal[nj];
                net.signal[nj] -= t;
                net.signal[ni] += t;
            }
        }
    }

    // Production + sum-form diffusion + decay at each node
    for (0..h) |y| {
        for (0..w) |x| {
            const i = y * w + x;
            if (net.is_boundary[i] != 0) continue;

            if (net.is_source[i] != 0) {
                net.signal[i] += net_mod.DT * net_mod.SIGNAL_PRODUCTION * net.food[i] / 255.0;
            }

            var diff: f32 = 0.0;
            if (x > 0) {
                const e = net.horizEdgeIndex(x - 1, y);
                if (net.active[e] != 0) diff += net.signal[y * w + (x - 1)] - net.signal[i];
            }
            if (x < w - 1) {
                const e = net.horizEdgeIndex(x, y);
                if (net.active[e] != 0) diff += net.signal[y * w + (x + 1)] - net.signal[i];
            }
            if (y > 0) {
                const e = net.vertEdgeIndex(x, y - 1);
                if (net.active[e] != 0) diff += net.signal[(y - 1) * w + x] - net.signal[i];
            }
            if (y < h - 1) {
                const e = net.vertEdgeIndex(x, y);
                if (net.active[e] != 0) diff += net.signal[(y + 1) * w + x] - net.signal[i];
            }
            net.signal[i] += net_mod.DT * net_mod.SIGNAL_DIFFUSION * diff;

            net.signal[i] *= (1.0 - net_mod.DT * net_mod.SIGNAL_DECAY);
            if (net.signal[i] < 0.0)   net.signal[i] = 0.0;
            if (net.signal[i] > 255.0) net.signal[i] = 255.0;
        }
    }
}

// Phase 6: softening agent — same upwind scheme as signal but slower decay.
pub fn advectSoftening(net: *Network) void {
    const w = net.width;
    const h = net.height;

    for (0..h) |y| {
        for (0..w - 1) |x| {
            const e = net.horizEdgeIndex(x, y);
            if (net.active[e] == 0) continue;
            const q  = net.flow[e];
            const ni = y * w + x;
            const nj = y * w + (x + 1);
            if (q > 0.0) {
                var t = net_mod.DT * q * net.softening[ni];
                if (t > net.softening[ni]) t = net.softening[ni];
                net.softening[ni] -= t;
                net.softening[nj] += t;
            } else if (q < 0.0) {
                var t = net_mod.DT * (-q) * net.softening[nj];
                if (t > net.softening[nj]) t = net.softening[nj];
                net.softening[nj] -= t;
                net.softening[ni] += t;
            }
        }
    }

    for (0..h - 1) |y| {
        for (0..w) |x| {
            const e = net.vertEdgeIndex(x, y);
            if (net.active[e] == 0) continue;
            const q  = net.flow[e];
            const ni = y * w + x;
            const nj = (y + 1) * w + x;
            if (q > 0.0) {
                var t = net_mod.DT * q * net.softening[ni];
                if (t > net.softening[ni]) t = net.softening[ni];
                net.softening[ni] -= t;
                net.softening[nj] += t;
            } else if (q < 0.0) {
                var t = net_mod.DT * (-q) * net.softening[nj];
                if (t > net.softening[nj]) t = net.softening[nj];
                net.softening[nj] -= t;
                net.softening[ni] += t;
            }
        }
    }

    for (0..h) |y| {
        for (0..w) |x| {
            const i = y * w + x;
            if (net.is_boundary[i] != 0) continue;

            var diff: f32 = 0.0;
            if (x > 0) {
                const e = net.horizEdgeIndex(x - 1, y);
                if (net.active[e] != 0) diff += net.softening[y * w + (x - 1)] - net.softening[i];
            }
            if (x < w - 1) {
                const e = net.horizEdgeIndex(x, y);
                if (net.active[e] != 0) diff += net.softening[y * w + (x + 1)] - net.softening[i];
            }
            if (y > 0) {
                const e = net.vertEdgeIndex(x, y - 1);
                if (net.active[e] != 0) diff += net.softening[(y - 1) * w + x] - net.softening[i];
            }
            if (y < h - 1) {
                const e = net.vertEdgeIndex(x, y);
                if (net.active[e] != 0) diff += net.softening[(y + 1) * w + x] - net.softening[i];
            }
            net.softening[i] += net_mod.DT * net_mod.SOFTENING_DIFFUSION * diff;

            net.softening[i] *= (1.0 - net_mod.DT * net_mod.SOFTENING_DECAY);
            if (net.softening[i] < 0.0)   net.softening[i] = 0.0;
            if (net.softening[i] > 255.0) net.softening[i] = 255.0;
        }
    }
}

// Phase 7: consume food at source nodes; trigger softening burst on depletion.
pub fn updateFood(net: *Network) void {
    const w = net.width;
    const h = net.height;

    for (0..h) |y| {
        for (0..w) |x| {
            const i = y * w + x;
            if (net.is_source[i] == 0 or net.food[i] <= 0.0) continue;

            var total_flow: f32 = 0.0;
            if (x > 0) {
                const e = net.horizEdgeIndex(x - 1, y);
                if (net.active[e] != 0) total_flow += @abs(net.flow[e]);
            }
            if (x < w - 1) {
                const e = net.horizEdgeIndex(x, y);
                if (net.active[e] != 0) total_flow += @abs(net.flow[e]);
            }
            if (y > 0) {
                const e = net.vertEdgeIndex(x, y - 1);
                if (net.active[e] != 0) total_flow += @abs(net.flow[e]);
            }
            if (y < h - 1) {
                const e = net.vertEdgeIndex(x, y);
                if (net.active[e] != 0) total_flow += @abs(net.flow[e]);
            }

            net.food[i] -= net_mod.DT * net_mod.CONSUMPTION_RATE * total_flow * (net.food[i] / 255.0);
            if (net.food[i] < 0.0) net.food[i] = 0.0;

            if (net.food[i] < net_mod.FOOD_DEPLETED_THRESHOLD) {
                net.softening[i] += net_mod.SOFTENING_BURST;
                net.is_source[i]  = 0;
                net.food[i]       = 0.0;
            }
        }
    }
}

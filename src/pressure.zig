// Gauss-Seidel pressure solver (doc 08 Phase 2, doc 10 section 3)
// Dirichlet BCs: source P = PRESSURE_SOURCE, sink P = 0.
// Interior nodes updated via conductance-weighted neighbor average using D_eff.

const net_mod = @import("network.zig");
const Network = net_mod.Network;

pub fn solve(net: *Network) void {
    const w = net.width;
    const h = net.height;

    for (0..net.node_count) |i| {
        if (net.is_source[i] != 0) {
            net.pressure[i] = net_mod.PRESSURE_SOURCE;
        } else if (net.is_sink[i] != 0) {
            net.pressure[i] = 0.0;
        }
    }

    var has_source = false;
    var has_sink   = false;
    for (0..net.node_count) |i| {
        if (net.is_source[i] != 0) has_source = true;
        if (net.is_sink[i]   != 0) has_sink   = true;
        if (has_source and has_sink) break;
    }
    if (!has_source or !has_sink) return;

    for (0..net_mod.GAUSS_ITER) |_| {
        for (0..h) |y| {
            for (0..w) |x| {
                const i = y * w + x;
                if (net.is_source[i]   != 0) continue;
                if (net.is_sink[i]     != 0) continue;
                if (net.is_boundary[i] != 0) continue;

                var num: f32 = 0.0;
                var den: f32 = 0.0;

                if (x > 0) {
                    const e = net.horizEdgeIndex(x - 1, y);
                    if (net.active[e] != 0) {
                        const d = net.d_eff[e];
                        num += d * net.pressure[y * w + (x - 1)];
                        den += d;
                    }
                }
                if (x < w - 1) {
                    const e = net.horizEdgeIndex(x, y);
                    if (net.active[e] != 0) {
                        const d = net.d_eff[e];
                        num += d * net.pressure[y * w + (x + 1)];
                        den += d;
                    }
                }
                if (y > 0) {
                    const e = net.vertEdgeIndex(x, y - 1);
                    if (net.active[e] != 0) {
                        const d = net.d_eff[e];
                        num += d * net.pressure[(y - 1) * w + x];
                        den += d;
                    }
                }
                if (y < h - 1) {
                    const e = net.vertEdgeIndex(x, y);
                    if (net.active[e] != 0) {
                        const d = net.d_eff[e];
                        num += d * net.pressure[(y + 1) * w + x];
                        den += d;
                    }
                }

                if (den > 0.0001) net.pressure[i] = num / den;
            }
        }
    }
}

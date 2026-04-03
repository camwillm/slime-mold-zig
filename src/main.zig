const std        = @import("std");
const net_mod    = @import("network.zig");
const pressure   = @import("pressure.zig");
const adapt      = @import("adapt.zig");
const signal_mod = @import("signal.zig");

const allocator = std.heap.page_allocator;

var network:     net_mod.Network = undefined;
var initialized: bool            = false;
var tick:        u64             = 0;

var food_count:       u32   = 0;
var first_food_idx:   usize = 0;
var default_sink_idx: usize = 0;

var rng_state: u32 = 54321;
var debug_active_after_init: u32 = 0;

fn xorshift(s: *u32) f32 {
    s.* ^= s.* << 13;
    s.* ^= s.* >> 17;
    s.* ^= s.* << 5;
    return @as(f32, @floatFromInt(s.* & 0xFFFF)) / 65536.0;
}

// Spiderweb growth model: activate only edges within INITIAL_RADIUS of grid center.
// All other edges start inactive (zero conductance). The frontier expands every 10 ticks
// guided by the food gradient (see adapt.expandFrontier).
fn spiderwebInit() void {
    // Zero all edges first — ensures clean state regardless of what called us.
    @memset(network.active,      0);
    @memset(network.conductance, 0);
    @memset(network.d_eff,       0);

    const cx: i32 = @intCast(net_mod.WIDTH  / 2);
    const cy: i32 = @intCast(net_mod.HEIGHT / 2);
    const r: f32  = @floatFromInt(net_mod.INITIAL_RADIUS);

    for (0..net_mod.HORIZ_EDGES) |e| {
        const row: i32 = @intCast(e / (net_mod.WIDTH - 1));
        const col: i32 = @intCast(e % (net_mod.WIDTH - 1));
        const dx: f32  = @floatFromInt(col - cx);
        const dy: f32  = @floatFromInt(row - cy);
        if (@sqrt(dx * dx + dy * dy) <= r) {
            network.active[e]      = 1;
            network.conductance[e] = net_mod.INITIAL_CONDUCTANCE + xorshift(&rng_state) * 0.004;
            network.d_eff[e]       = network.conductance[e];
        }
    }

    for (0..net_mod.VERT_EDGES) |e| {
        const row: i32 = @intCast(e / net_mod.WIDTH);
        const col: i32 = @intCast(e % net_mod.WIDTH);
        const dx: f32  = @floatFromInt(col - cx);
        const dy: f32  = @floatFromInt(row - cy);
        if (@sqrt(dx * dx + dy * dy) <= r) {
            const ei               = net_mod.HORIZ_EDGES + e;
            network.active[ei]      = 1;
            network.conductance[ei] = net_mod.INITIAL_CONDUCTANCE + xorshift(&rng_state) * 0.004;
            network.d_eff[ei]       = network.conductance[ei];
        }
    }

    // Capture count for debug export — measured inside this function, not affected by JS timing.
    var dbg: u32 = 0;
    for (network.active) |a| { if (a != 0) dbg += 1; }
    debug_active_after_init = dbg;
}

export fn getDebugActiveCount() u32 { return debug_active_after_init; }

export fn init(width: u32, height: u32) void {
    if (initialized) {
        network.deinit();
        initialized = false;
    }
    const w = @as(usize, width);
    const h = @as(usize, height);
    network = net_mod.Network.init(allocator, w, h) catch return;
    default_sink_idx = (h / 2) * w + (w / 2);
    tick       = 0;
    food_count = 0;
    initialized = true;
    spiderwebInit();
}

export fn reset() void {
    if (!initialized) return;
    network.reset();
    default_sink_idx = (network.height / 2) * network.width + (network.width / 2);
    tick       = 0;
    food_count = 0;
    spiderwebInit();
}

// Full simulation tick — all phases in order (doc 08):
//   Phase 1: peristalsis + D_eff
//   Phase 2: pressure
//   Phase 3: flow
//   Phase 4: conductance adaptation
//   Phase 5: signal advection
//   Phase 6: softening advection
//   Phase 7: food consumption
export fn step() void {
    if (!initialized) return;
    tick += 1;
    adapt.advancePhases(&network);
    pressure.solve(&network);
    adapt.calcFlow(&network);
    adapt.updateConductance(&network);
    signal_mod.advectSignal(&network);
    signal_mod.advectSoftening(&network);
    signal_mod.updateFood(&network);
    signal_mod.diffuseFoodGradient(&network);
    if (tick % 20 == 0) adapt.expandFrontier(&network);
}

// Pre-diffuse food gradient N times without advancing simulation tick.
// Call after placing food so the scent cloud reaches the blob before decay kills it.
export fn warmupGradient(steps: u32) void {
    if (!initialized) return;
    var i: u32 = 0;
    while (i < steps) : (i += 1) {
        signal_mod.diffuseFoodGradient(&network);
    }
}

// --- Food placement (doc 07 sink lifecycle, Phase 1 scheme) ---

export fn setFood(x: u32, y: u32, strength: f32) void {
    if (!initialized) return;
    const xi = @as(usize, x);
    const yi = @as(usize, y);
    if (xi >= network.width or yi >= network.height) return;

    const idx = yi * network.width + xi;
    network.food[idx]        = @min(@max(strength, 0.0), 255.0);
    network.is_boundary[idx] = 0;

    if (food_count == 0) {
        network.is_source[idx]            = 1;
        network.is_sink[default_sink_idx] = 1;
        first_food_idx = idx;
        food_count = 1;
    } else if (food_count == 1) {
        network.is_source[first_food_idx] = 0;
        network.is_sink[first_food_idx]   = 1;
        network.is_sink[default_sink_idx] = 0;
        network.is_source[idx]            = 1;
        food_count = 2;
    } else {
        network.is_source[idx] = 1;
        food_count += 1;
    }
}

export fn clearFood() void {
    if (!initialized) return;
    @memset(network.food,      0);
    @memset(network.is_source, 0);
    @memset(network.is_sink,   0);
    food_count = 0;
    network.is_sink[default_sink_idx] = 1;
}

// Direct placement — bypasses food_count lifecycle for explicit multi-node setups.
export fn addSource(x: u32, y: u32, strength: f32) void {
    if (!initialized) return;
    const xi = @as(usize, x);
    const yi = @as(usize, y);
    if (xi >= network.width or yi >= network.height) return;
    const idx = yi * network.width + xi;
    network.food[idx]        = @min(@max(strength, 0.0), 255.0);
    network.is_source[idx]   = 1;
    network.is_sink[idx]     = 0;  // never both
    network.is_boundary[idx] = 0;
    food_count += 1;
}

export fn addSink(x: u32, y: u32) void {
    if (!initialized) return;
    const xi = @as(usize, x);
    const yi = @as(usize, y);
    if (xi >= network.width or yi >= network.height) return;
    const idx = yi * network.width + xi;
    network.is_sink[idx]     = 1;
    network.is_source[idx]   = 0;  // never both
    network.is_boundary[idx] = 0;
}

// Seed food gradient at a location without changing pressure roles.
// Use for food sinks so the scent cloud diffuses toward the organism.
export fn seedGradient(x: u32, y: u32, v: f32) void {
    if (!initialized) return;
    const idx = @as(usize, y) * network.width + @as(usize, x);
    network.food[idx]          = @min(@max(v, 0.0), 255.0);
    network.food_gradient[idx] = network.food[idx];
}

// --- Memory pointers ---

export fn getPressurePtr()      [*]f32 { return network.pressure.ptr; }
export fn getConductancePtr()   [*]f32 { return network.conductance.ptr; }
export fn getFlowPtr()          [*]f32 { return network.flow.ptr; }
export fn getSignalPtr()        [*]f32 { return network.signal.ptr; }
export fn getPhasePtr()         [*]f32 { return network.phase.ptr; }
export fn getFoodPtr()          [*]f32 { return network.food.ptr; }
export fn getSofteningPtr()     [*]f32 { return network.softening.ptr; }
export fn getFoodGradientPtr()  [*]f32 { return network.food_gradient.ptr; }

export fn getTick() u64 { return tick; }

// --- Counts ---

export fn getNodeCount()      u32 { return @intCast(network.node_count); }
export fn getHorizEdgeCount() u32 { return @intCast(network.horiz_count); }
export fn getVertEdgeCount()  u32 { return @intCast(network.vert_count); }
export fn getTotalEdgeCount() u32 { return @intCast(network.edge_count); }
export fn getWidth()          u32 { return @intCast(network.width); }
export fn getHeight()         u32 { return @intCast(network.height); }

// --- Stats ---

export fn getActiveEdgeCount() u32 {
    if (!initialized) return 0;
    var count: u32 = 0;
    for (network.active) |a| { if (a != 0) count += 1; }
    return count;
}

export fn getActiveNodeCount() u32 {
    if (!initialized) return 0;
    const w = network.width;
    const h = network.height;
    var node_active = [_]bool{false} ** net_mod.TOTAL_NODES;
    for (0..h) |y| {
        for (0..w - 1) |x| {
            const e = network.horizEdgeIndex(x, y);
            if (network.active[e] != 0) {
                node_active[y * w + x]       = true;
                node_active[y * w + (x + 1)] = true;
            }
        }
    }
    for (0..h - 1) |y| {
        for (0..w) |x| {
            const e = network.vertEdgeIndex(x, y);
            if (network.active[e] != 0) {
                node_active[y * w + x]       = true;
                node_active[(y + 1) * w + x] = true;
            }
        }
    }
    var count: u32 = 0;
    for (node_active) |a| { if (a) count += 1; }
    return count;
}

export fn getMajorVeinCount() u32 {
    if (!initialized) return 0;
    var count: u32 = 0;
    for (network.conductance) |d| { if (d > 2.0) count += 1; }
    return count;
}

export fn getSignalNodeCount() u32 {
    if (!initialized) return 0;
    var count: u32 = 0;
    for (network.signal) |s| { if (s > 20.0) count += 1; }
    return count;
}

export fn getFoodRemaining() f32 {
    if (!initialized) return 0;
    var sum: f32 = 0;
    for (network.food) |f| sum += f;
    return sum;
}

export fn getMaxConductance() f32 {
    if (!initialized) return 0;
    var max: f32 = 0;
    for (network.conductance) |d| { if (d > max) max = d; }
    return max;
}

export fn getAvgFlow() f32 {
    if (!initialized) return 0;
    var sum: f32 = 0;
    var cnt: u32 = 0;
    for (network.flow, network.active) |q, a| {
        if (a != 0) { sum += @abs(q); cnt += 1; }
    }
    return if (cnt > 0) sum / @as(f32, @floatFromInt(cnt)) else 0;
}

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    _ = msg;
    _ = error_return_trace;
    _ = ret_addr;
    @trap();
}

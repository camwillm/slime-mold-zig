const std = @import("std");

// --- Simulation constants (doc 10) ---
pub const INITIAL_CONDUCTANCE:    f32   = 0.01;
pub const MIN_CONDUCTANCE:        f32   = 0.0001;
pub const MAX_CONDUCTANCE:        f32   = 10.0;
pub const REACTIVATION_THRESHOLD: f32   = 0.001;
pub const PRESSURE_SOURCE:        f32   = 1.0;
pub const MU:                     f32   = 1.0;
pub const DECAY:                  f32   = 0.01;
pub const DT:                     f32   = 0.1;
pub const GAUSS_ITER:             usize = 25;

// Peristalsis (Alim 2013)
pub const OMEGA:          f32 = std.math.tau / 100.0; // 2π/100 — 100-tick period
pub const K:              f32 = 0.1;                  // Kuramoto coupling strength
pub const AMPLITUDE:      f32 = 0.3;                  // base peristaltic amplitude
pub const SIGNAL_COUPLING: f32 = 0.02;                // signal → amplitude (Alim 2017)

// Signal cAMP (Alim 2017)
pub const SIGNAL_DIFFUSION:  f32 = 0.01;
pub const SIGNAL_PRODUCTION: f32 = 5.0;
pub const SIGNAL_DECAY:      f32 = 0.005;

// Softening / structural memory (Kramar & Alim 2021)
pub const SOFTENING_DIFFUSION: f32 = 0.005;
pub const SOFTENING_DECAY:     f32 = 0.001;
pub const SOFTENING_BURST:     f32 = 50.0;
pub const SOFTENING_WEIGHT:    f32 = 0.1;

// Food consumption
pub const CONSUMPTION_RATE:      f32 = 0.001;
pub const FOOD_DEPLETED_THRESHOLD: f32 = 5.0;

pub const Network = struct {
    width:       usize,
    height:      usize,
    node_count:  usize,
    horiz_count: usize,
    vert_count:  usize,
    edge_count:  usize,

    // Node arrays [node_count]
    pressure:    []f32,
    signal:      []f32,
    calcium:     []f32,
    food:        []f32,
    softening:   []f32,
    is_source:   []u8,
    is_sink:     []u8,
    is_boundary: []u8,

    // Edge arrays [edge_count]
    conductance: []f32,
    flow:        []f32,
    phase:       []f32,  // peristaltic phase per edge, initialized random in [0, 2π]
    d_eff:       []f32,  // effective conductance = D*(1+A*sin(φ)), recomputed each tick
    active:      []u8,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Network {
        const node_count  = width * height;
        const horiz_count = (width - 1) * height;
        const vert_count  = width * (height - 1);
        const edge_count  = horiz_count + vert_count;

        const pressure    = try allocator.alloc(f32, node_count);
        errdefer allocator.free(pressure);
        @memset(pressure, 0);

        const signal      = try allocator.alloc(f32, node_count);
        errdefer allocator.free(signal);
        @memset(signal, 0);

        const calcium     = try allocator.alloc(f32, node_count);
        errdefer allocator.free(calcium);
        @memset(calcium, 0);

        const food        = try allocator.alloc(f32, node_count);
        errdefer allocator.free(food);
        @memset(food, 0);

        const softening   = try allocator.alloc(f32, node_count);
        errdefer allocator.free(softening);
        @memset(softening, 0);

        const is_source   = try allocator.alloc(u8, node_count);
        errdefer allocator.free(is_source);
        @memset(is_source, 0);

        const is_sink     = try allocator.alloc(u8, node_count);
        errdefer allocator.free(is_sink);
        @memset(is_sink, 0);

        const is_boundary = try allocator.alloc(u8, node_count);
        errdefer allocator.free(is_boundary);
        @memset(is_boundary, 0);

        const conductance = try allocator.alloc(f32, edge_count);
        errdefer allocator.free(conductance);
        @memset(conductance, INITIAL_CONDUCTANCE);

        const flow        = try allocator.alloc(f32, edge_count);
        errdefer allocator.free(flow);
        @memset(flow, 0);

        const phase       = try allocator.alloc(f32, edge_count);
        errdefer allocator.free(phase);
        @memset(phase, 0);

        const d_eff       = try allocator.alloc(f32, edge_count);
        errdefer allocator.free(d_eff);
        @memset(d_eff, INITIAL_CONDUCTANCE);

        const active      = try allocator.alloc(u8, edge_count);
        errdefer allocator.free(active);
        @memset(active, 1);

        var net = Network{
            .width       = width,
            .height      = height,
            .node_count  = node_count,
            .horiz_count = horiz_count,
            .vert_count  = vert_count,
            .edge_count  = edge_count,
            .pressure    = pressure,
            .signal      = signal,
            .calcium     = calcium,
            .food        = food,
            .softening   = softening,
            .is_source   = is_source,
            .is_sink     = is_sink,
            .is_boundary = is_boundary,
            .conductance = conductance,
            .flow        = flow,
            .phase       = phase,
            .d_eff       = d_eff,
            .active      = active,
            .allocator   = allocator,
        };

        net.initBoundaries();
        net.randomizePhases(42);
        net.is_sink[(height / 2) * width + (width / 2)] = 1;
        return net;
    }

    pub fn reset(self: *Network) void {
        @memset(self.pressure,    0);
        @memset(self.signal,      0);
        @memset(self.calcium,     0);
        @memset(self.food,        0);
        @memset(self.softening,   0);
        @memset(self.is_source,   0);
        @memset(self.is_sink,     0);
        @memset(self.is_boundary, 0);
        @memset(self.conductance, INITIAL_CONDUCTANCE);
        @memset(self.flow,        0);
        @memset(self.d_eff,       INITIAL_CONDUCTANCE);
        @memset(self.active,      1);

        self.initBoundaries();
        self.randomizePhases(42);
        self.is_sink[(self.height / 2) * self.width + (self.width / 2)] = 1;
    }

    pub fn deinit(self: *Network) void {
        self.allocator.free(self.pressure);
        self.allocator.free(self.signal);
        self.allocator.free(self.calcium);
        self.allocator.free(self.food);
        self.allocator.free(self.softening);
        self.allocator.free(self.is_source);
        self.allocator.free(self.is_sink);
        self.allocator.free(self.is_boundary);
        self.allocator.free(self.conductance);
        self.allocator.free(self.flow);
        self.allocator.free(self.phase);
        self.allocator.free(self.d_eff);
        self.allocator.free(self.active);
    }

    // Xorshift32 seeded random phases in [0, 2π].
    fn randomizePhases(self: *Network, seed: u32) void {
        var s = seed;
        for (self.phase) |*p| {
            s ^= s << 13;
            s ^= s >> 17;
            s ^= s << 5;
            p.* = @as(f32, @floatFromInt(s & 0xFFFF)) / 65536.0 * std.math.tau;
        }
    }

    fn initBoundaries(self: *Network) void {
        const w = self.width;
        const h = self.height;

        for (0..w) |x| {
            self.is_boundary[x] = 1;
            self.is_boundary[(h - 1) * w + x] = 1;
        }
        for (0..h) |y| {
            self.is_boundary[y * w] = 1;
            self.is_boundary[y * w + (w - 1)] = 1;
        }

        for (0..h) |y| {
            for (0..w - 1) |x| {
                if (self.is_boundary[y * w + x] != 0 or self.is_boundary[y * w + (x + 1)] != 0) {
                    const e = self.horizEdgeIndex(x, y);
                    self.active[e]      = 0;
                    self.conductance[e] = MIN_CONDUCTANCE;
                    self.d_eff[e]       = MIN_CONDUCTANCE;
                }
            }
        }

        for (0..h - 1) |y| {
            for (0..w) |x| {
                if (self.is_boundary[y * w + x] != 0 or self.is_boundary[(y + 1) * w + x] != 0) {
                    const e = self.vertEdgeIndex(x, y);
                    self.active[e]      = 0;
                    self.conductance[e] = MIN_CONDUCTANCE;
                    self.d_eff[e]       = MIN_CONDUCTANCE;
                }
            }
        }
    }

    pub inline fn horizEdgeIndex(self: *const Network, x: usize, y: usize) usize {
        return y * (self.width - 1) + x;
    }

    pub inline fn vertEdgeIndex(self: *const Network, x: usize, y: usize) usize {
        return self.horiz_count + y * self.width + x;
    }
};

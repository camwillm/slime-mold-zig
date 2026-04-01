const std = @import("std");
const Sim = @import("sim.zig").Sim;

const allocator = std.heap.page_allocator;

var sim: Sim = undefined;
var diffuse_buffer: []f32 = undefined;
var rng: std.Random.DefaultPrng = undefined;
var initialized: bool = false;

export fn init(width: u32, height: u32) void {
    if (initialized) {
        sim.deinit();
        allocator.free(diffuse_buffer);
        initialized = false;
    }
    sim = Sim.init(allocator, @as(usize, width), @as(usize, height)) catch return;
    diffuse_buffer = allocator.alloc(f32, @as(usize, width) * @as(usize, height)) catch {
        sim.deinit();
        return;
    };
    rng = std.Random.DefaultPrng.init(12345);
    initialized = true;
}

export fn step() void {
    if (!initialized) return;
    sim.step(&rng);
    sim.decayAndDiffuse(diffuse_buffer);
}

export fn getGridPtr() [*]f32 {
    return sim.grid.cells.ptr;
}

export fn getGridLen() u32 {
    return @intCast(sim.grid.cells.len);
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = msg;
    _ = error_return_trace;
    _ = ret_addr;
    @trap();
}

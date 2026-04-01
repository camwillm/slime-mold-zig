const std = @import("std");

// The trail map is a flat array of f32 values
// We use a 1D array to represent a 2D grid: index = y * width + x
// This is cache-friendly — sequential memory access is faster than 2D arrays
pub const Grid = struct {
    width: usize,
    height: usize,
    cells: []f32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Grid {
        const cells = try allocator.alloc(f32, width * height);
        @memset(cells, 0);
        return Grid{
            .width = width,
            .height = height,
            .cells = cells,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Grid) void {
        self.allocator.free(self.cells);
    }

    pub fn get(self: *Grid, x: usize, y: usize) f32 {
        return self.cells[y * self.width + x];
    }

    pub fn set(self: *Grid, x: usize, y: usize, value: f32) void {
        self.cells[y * self.width + x] = value;
    }
};

// Each agent has a position and direction angle in radians
pub const Agent = struct {
    x: f32,
    y: f32,
    angle: f32,
};

pub const Sim = struct {
    grid: Grid,
    agents: []Agent,
    allocator: std.mem.Allocator,

    pub const AGENT_COUNT: usize = 10_000;
    pub const SENSOR_ANGLE: f32 = 0.4;
    pub const SENSOR_DISTANCE: f32 = 9.0;
    pub const TURN_SPEED: f32 = 0.3;
    pub const MOVE_SPEED: f32 = 1.0;
    pub const DEPOSIT_AMOUNT: f32 = 5.0;
    pub const DECAY_RATE: f32 = 0.95;

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Sim {
        var grid = try Grid.init(allocator, width, height);
        errdefer grid.deinit();

        const agents = try allocator.alloc(Agent, AGENT_COUNT);

        // Spawn agents in a circle at center
        var rng = std.rand.DefaultPrng.init(42);
        const rand = rng.random();
        const cx = @as(f32, @floatFromInt(width)) / 2.0;
        const cy = @as(f32, @floatFromInt(height)) / 2.0;

        for (agents) |*agent| {
            const angle = rand.float(f32) * std.math.tau;
            const radius = rand.float(f32) * 50.0;
            agent.* = Agent{
                .x = cx + @cos(angle) * radius,
                .y = cy + @sin(angle) * radius,
                .angle = angle,
            };
        }

        return Sim{
            .grid = grid,
            .agents = agents,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Sim) void {
        self.grid.deinit();
        self.allocator.free(self.agents);
    }

    pub fn step(self: *Sim, rng: *std.rand.Xoshiro256) void {
        for (self.agents) |*agent| {
            const fl = sampleTrail(&self.grid, agent.x, agent.y, agent.angle + SENSOR_ANGLE, SENSOR_DISTANCE);
            const f  = sampleTrail(&self.grid, agent.x, agent.y, agent.angle, SENSOR_DISTANCE);
            const fr = sampleTrail(&self.grid, agent.x, agent.y, agent.angle - SENSOR_ANGLE, SENSOR_DISTANCE);

            if (f >= fl and f >= fr) {
                // stay straight
            } else if (fl > fr) {
                agent.angle += TURN_SPEED;
            } else if (fr > fl) {
                agent.angle -= TURN_SPEED;
            } else {
                // random jitter prevents agents locking up when sides are equal
                const jitter = rng.random().float(f32) - 0.5;
                agent.angle += jitter * TURN_SPEED;
            }

            const new_x = agent.x + @cos(agent.angle) * MOVE_SPEED;
            const new_y = agent.y + @sin(agent.angle) * MOVE_SPEED;

            // Wrap edges so agents stay in bounds without bouncing
            agent.x = @mod(new_x + @as(f32, @floatFromInt(self.grid.width)), @as(f32, @floatFromInt(self.grid.width)));
            agent.y = @mod(new_y + @as(f32, @floatFromInt(self.grid.height)), @as(f32, @floatFromInt(self.grid.height)));

            const ix = @as(usize, @intFromFloat(agent.x));
            const iy = @as(usize, @intFromFloat(agent.y));
            self.grid.set(ix, iy, @min(self.grid.get(ix, iy) + DEPOSIT_AMOUNT, 255.0));
        }
    }

    // Write to separate buffer so we don't read already-diffused values mid-pass
    pub fn decayAndDiffuse(self: *Sim, buffer: []f32) void {
        const w = self.grid.width;
        const h = self.grid.height;

        for (1..h - 1) |y| {
            for (1..w - 1) |x| {
                var sum: f32 = 0;
                sum += self.grid.get(x - 1, y - 1);
                sum += self.grid.get(x,     y - 1);
                sum += self.grid.get(x + 1, y - 1);
                sum += self.grid.get(x - 1, y    );
                sum += self.grid.get(x,     y    );
                sum += self.grid.get(x + 1, y    );
                sum += self.grid.get(x - 1, y + 1);
                sum += self.grid.get(x,     y + 1);
                sum += self.grid.get(x + 1, y + 1);

                buffer[y * w + x] = (sum / 9.0) * DECAY_RATE;
            }
        }

        @memcpy(self.grid.cells, buffer);
    }

    fn sampleTrail(grid: *Grid, x: f32, y: f32, angle: f32, distance: f32) f32 {
        const sx = x + @cos(angle) * distance;
        const sy = y + @sin(angle) * distance;

        const wx = @mod(sx + @as(f32, @floatFromInt(grid.width)), @as(f32, @floatFromInt(grid.width)));
        const wy = @mod(sy + @as(f32, @floatFromInt(grid.height)), @as(f32, @floatFromInt(grid.height)));

        const ix = @as(usize, @intFromFloat(wx));
        const iy = @as(usize, @intFromFloat(wy));
        return grid.get(ix, iy);
    }
};
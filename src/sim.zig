const std = @import("std");

pub const Grid = struct {
    width: usize,
    height: usize,
    cells: []f32,
    food: []f32,
    food_strength: []f32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Grid {
        const cells = try allocator.alloc(f32, width * height);
        errdefer allocator.free(cells);
        @memset(cells, 0);
        const food = try allocator.alloc(f32, width * height);
        errdefer allocator.free(food);
        @memset(food, 0);
        const food_strength = try allocator.alloc(f32, width * height);
        @memset(food_strength, 0);
        return Grid{
            .width = width,
            .height = height,
            .cells = cells,
            .food = food,
            .food_strength = food_strength,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Grid) void {
        self.allocator.free(self.cells);
        self.allocator.free(self.food);
        self.allocator.free(self.food_strength);
    }

    pub fn get(self: *Grid, x: usize, y: usize) f32 {
        return self.cells[y * self.width + x];
    }

    pub fn set(self: *Grid, x: usize, y: usize, value: f32) void {
        self.cells[y * self.width + x] = value;
    }

    pub fn getFood(self: *Grid, x: usize, y: usize) f32 {
        return self.food[y * self.width + x];
    }

    /// Sets both the food diffusion map and the food_strength tracking array.
    pub fn setFood(self: *Grid, x: usize, y: usize, value: f32) void {
        const idx = y * self.width + x;
        self.food[idx] = value;
        self.food_strength[idx] = value;
    }

    pub fn getFoodStrength(self: *Grid, x: usize, y: usize) f32 {
        return self.food_strength[y * self.width + x];
    }
};

pub const AgentState = enum { exploring, returning };

pub const Agent = struct {
    x: f32,
    y: f32,
    angle: f32,
    state: AgentState,
    food_x: f32,
    food_y: f32,
};

pub const Sim = struct {
    grid: Grid,
    agents: []Agent,
    active_count: usize,
    allocator: std.mem.Allocator,

    pub const AGENT_COUNT: usize = 50_000;
    pub const STARTING_AGENTS: usize = 1_000;
    pub const SPAWN_PER_RETURN: usize = 2;
    pub const FOOD_CONSUMPTION_PER_RETURN: f32 = 15.0;
    pub const FOOD_DIFFUSION_BLEND: f32 = 0.05;
    pub const SENSOR_ANGLE: f32 = 0.4;
    pub const FOOD_THRESHOLD: f32 = 120.0;
    pub const DECAY_RATE: f32 = 0.982;
    pub const DEPOSIT_AMOUNT: f32 = 3.0;
    pub const SENSOR_DISTANCE: f32 = 12.0;
    pub const TURN_SPEED: f32 = 0.35;
    pub const MOVE_SPEED: f32 = 1.0;

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Sim {
        var grid = try Grid.init(allocator, width, height);
        errdefer grid.deinit();

        const agents = try allocator.alloc(Agent, AGENT_COUNT);

        var rng = std.Random.DefaultPrng.init(42);
        const rand = rng.random();
        const cx = @as(f32, @floatFromInt(width)) / 2.0;
        const cy = @as(f32, @floatFromInt(height)) / 2.0;

        for (0..STARTING_AGENTS) |i| {
            const angle = rand.float(f32) * std.math.tau;
            const radius = rand.float(f32) * 20.0;
            agents[i] = Agent{
                .x = cx + @cos(angle) * radius,
                .y = cy + @sin(angle) * radius,
                .angle = angle,
                .state = .exploring,
                .food_x = 0,
                .food_y = 0,
            };
        }

        return Sim{
            .grid = grid,
            .agents = agents,
            .active_count = STARTING_AGENTS,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Sim) void {
        self.grid.deinit();
        self.allocator.free(self.agents);
    }

    fn spawnAgent(self: *Sim, x: f32, y: f32, angle: f32) void {
        if (self.active_count >= AGENT_COUNT) return;
        self.agents[self.active_count] = Agent{
            .x = x,
            .y = y,
            .angle = angle,
            .state = .exploring,
            .food_x = 0,
            .food_y = 0,
        };
        self.active_count += 1;
    }

    pub fn step(self: *Sim, rng: *std.Random.Xoshiro256) void {
        const fw = @as(f32, @floatFromInt(self.grid.width));
        const fh = @as(f32, @floatFromInt(self.grid.height));
        const cx = fw / 2.0;
        const cy = fh / 2.0;

        // Snapshot active_count — newly spawned agents are picked up next step
        const count = self.active_count;

        for (self.agents[0..count]) |*agent| {
            switch (agent.state) {
                .exploring => {
                    const food_fl = sampleFood(&self.grid, agent.x, agent.y, agent.angle + SENSOR_ANGLE, SENSOR_DISTANCE);
                    const food_f  = sampleFood(&self.grid, agent.x, agent.y, agent.angle,                SENSOR_DISTANCE);
                    const food_fr = sampleFood(&self.grid, agent.x, agent.y, agent.angle - SENSOR_ANGLE, SENSOR_DISTANCE);

                    if (food_fl > FOOD_THRESHOLD or food_f > FOOD_THRESHOLD or food_fr > FOOD_THRESHOLD) {
                        // Record sensor position of the strongest food signal
                        const best_angle = if (food_fl >= food_f and food_fl >= food_fr)
                            agent.angle + SENSOR_ANGLE
                        else if (food_f >= food_fr)
                            agent.angle
                        else
                            agent.angle - SENSOR_ANGLE;
                        const sx = agent.x + @cos(best_angle) * SENSOR_DISTANCE;
                        const sy = agent.y + @sin(best_angle) * SENSOR_DISTANCE;
                        agent.food_x = @mod(sx + fw, fw);
                        agent.food_y = @mod(sy + fh, fh);
                        agent.state = .returning;
                        agent.angle += std.math.pi;
                    } else {
                        // Trail repulsion: steer toward least-explored space
                        const fl = sampleTrail(&self.grid, agent.x, agent.y, agent.angle + SENSOR_ANGLE, SENSOR_DISTANCE);
                        const f  = sampleTrail(&self.grid, agent.x, agent.y, agent.angle,                SENSOR_DISTANCE);
                        const fr = sampleTrail(&self.grid, agent.x, agent.y, agent.angle - SENSOR_ANGLE, SENSOR_DISTANCE);

                        if (f >= fl and f >= fr) {
                            const jitter = rng.random().float(f32) - 0.5;
                            agent.angle += jitter * TURN_SPEED * 2.0;
                        } else if (fl >= fr) {
                            agent.angle -= TURN_SPEED;
                        } else {
                            agent.angle += TURN_SPEED;
                        }

                        const new_x = agent.x + @cos(agent.angle) * MOVE_SPEED;
                        const new_y = agent.y + @sin(agent.angle) * MOVE_SPEED;
                        agent.x = @mod(new_x + fw, fw);
                        agent.y = @mod(new_y + fh, fh);

                        const ix = @as(usize, @intFromFloat(agent.x));
                        const iy = @as(usize, @intFromFloat(agent.y));
                        for (0..3) |ddy| {
                            for (0..3) |ddx| {
                                const nx = (ix + ddx + self.grid.width  - 1) % self.grid.width;
                                const ny = (iy + ddy + self.grid.height - 1) % self.grid.height;
                                self.grid.set(nx, ny, @min(self.grid.get(nx, ny) + DEPOSIT_AMOUNT, 255.0));
                            }
                        }
                    }
                },

                .returning => {
                    const to_cx = cx - agent.x;
                    const to_cy = cy - agent.y;
                    const dist = @sqrt(to_cx * to_cx + to_cy * to_cy);

                    if (dist < 30.0) {
                        // Reached center — consume food at the recorded position
                        const fx = @min(@as(usize, @intFromFloat(agent.food_x)), self.grid.width - 1);
                        const fy = @min(@as(usize, @intFromFloat(agent.food_y)), self.grid.height - 1);
                        const fidx = fy * self.grid.width + fx;

                        const new_strength = @max(self.grid.food_strength[fidx] - FOOD_CONSUMPTION_PER_RETURN, 0.0);
                        self.grid.food_strength[fidx] = new_strength;

                        if (new_strength <= 0.0) {
                            // Food fully consumed — clear food map in 30px radius
                            const fxi = @as(i32, @intCast(fx));
                            const fyi = @as(i32, @intCast(fy));
                            const radius: i32 = 30;
                            var dy: i32 = -radius;
                            while (dy <= radius) : (dy += 1) {
                                var dx: i32 = -radius;
                                while (dx <= radius) : (dx += 1) {
                                    if (dx * dx + dy * dy <= radius * radius) {
                                        const nx = fxi + dx;
                                        const ny = fyi + dy;
                                        if (nx >= 0 and ny >= 0) {
                                            const unx = @as(usize, @intCast(nx));
                                            const uny = @as(usize, @intCast(ny));
                                            if (unx < self.grid.width and uny < self.grid.height) {
                                                const ni = uny * self.grid.width + unx;
                                                self.grid.food[ni] = 0;
                                                self.grid.food_strength[ni] = 0;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Grow the colony — spawn new explorers at center
                        for (0..SPAWN_PER_RETURN) |_| {
                            const spawn_angle = rng.random().float(f32) * std.math.tau;
                            self.spawnAgent(cx, cy, spawn_angle);
                        }

                        // Flip back to exploring with random outward angle
                        agent.state = .exploring;
                        agent.angle = rng.random().float(f32) * std.math.tau;
                    } else {
                        // Navigate toward center, leaving heavy tube trail
                        agent.angle = std.math.atan2(to_cy, to_cx);

                        const new_x = agent.x + @cos(agent.angle) * MOVE_SPEED;
                        const new_y = agent.y + @sin(agent.angle) * MOVE_SPEED;
                        agent.x = @mod(new_x + fw, fw);
                        agent.y = @mod(new_y + fh, fh);

                        const ix = @as(usize, @intFromFloat(agent.x));
                        const iy = @as(usize, @intFromFloat(agent.y));
                        for (0..3) |ddy| {
                            for (0..3) |ddx| {
                                const nx = (ix + ddx + self.grid.width  - 1) % self.grid.width;
                                const ny = (iy + ddy + self.grid.height - 1) % self.grid.height;
                                self.grid.set(nx, ny, @min(self.grid.get(nx, ny) + DEPOSIT_AMOUNT * 4.0, 255.0));
                            }
                        }
                    }
                },
            }
        }
    }

    pub fn decayAndDiffuse(self: *Sim, buffer: []f32) void {
        const w = self.grid.width;
        const h = self.grid.height;

        // Pass 1: Decay and blur trail map
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

        // Pass 2: Diffuse food map with slow blend; source cells are preserved
        for (1..h - 1) |y| {
            for (1..w - 1) |x| {
                const idx = y * w + x;
                const strength = self.grid.food_strength[idx];
                if (strength > 0.0) {
                    // Source cell — keep at current food_strength
                    buffer[idx] = strength;
                } else {
                    // Non-source — blend toward neighbor average
                    var sum: f32 = 0;
                    sum += self.grid.getFood(x - 1, y - 1);
                    sum += self.grid.getFood(x,     y - 1);
                    sum += self.grid.getFood(x + 1, y - 1);
                    sum += self.grid.getFood(x - 1, y    );
                    sum += self.grid.getFood(x,     y    );
                    sum += self.grid.getFood(x + 1, y    );
                    sum += self.grid.getFood(x - 1, y + 1);
                    sum += self.grid.getFood(x,     y + 1);
                    sum += self.grid.getFood(x + 1, y + 1);

                    const avg = sum / 9.0;
                    const current = self.grid.food[idx];
                    var blended = current + (avg - current) * FOOD_DIFFUSION_BLEND;

                    // Hard cap: diffused signal cannot exceed 30% of any adjacent source
                    var max_src: f32 = 0;
                    max_src = @max(max_src, self.grid.food_strength[(y - 1) * w + (x - 1)]);
                    max_src = @max(max_src, self.grid.food_strength[(y - 1) * w +  x     ]);
                    max_src = @max(max_src, self.grid.food_strength[(y - 1) * w + (x + 1)]);
                    max_src = @max(max_src, self.grid.food_strength[ y      * w + (x - 1)]);
                    max_src = @max(max_src, self.grid.food_strength[ y      * w + (x + 1)]);
                    max_src = @max(max_src, self.grid.food_strength[(y + 1) * w + (x - 1)]);
                    max_src = @max(max_src, self.grid.food_strength[(y + 1) * w +  x     ]);
                    max_src = @max(max_src, self.grid.food_strength[(y + 1) * w + (x + 1)]);

                    if (max_src > 0.0) {
                        blended = @min(blended, max_src * 0.3);
                    }
                    buffer[idx] = @max(blended, 0.0);
                }
            }
        }
        // Write back to food only (not food_strength)
        for (1..h - 1) |y| {
            for (1..w - 1) |x| {
                self.grid.food[y * w + x] = buffer[y * w + x];
            }
        }
    }

    // Trail sample: used for repulsion-based steering
    fn sampleTrail(grid: *Grid, x: f32, y: f32, angle: f32, distance: f32) f32 {
        const sx = x + @cos(angle) * distance;
        const sy = y + @sin(angle) * distance;
        const wx = @mod(sx + @as(f32, @floatFromInt(grid.width)),  @as(f32, @floatFromInt(grid.width)));
        const wy = @mod(sy + @as(f32, @floatFromInt(grid.height)), @as(f32, @floatFromInt(grid.height)));
        const ix = @as(usize, @intFromFloat(wx));
        const iy = @as(usize, @intFromFloat(wy));
        return grid.get(ix, iy);
    }

    // Food sample: used for food-detection state change
    fn sampleFood(grid: *Grid, x: f32, y: f32, angle: f32, distance: f32) f32 {
        const sx = x + @cos(angle) * distance;
        const sy = y + @sin(angle) * distance;
        const wx = @mod(sx + @as(f32, @floatFromInt(grid.width)),  @as(f32, @floatFromInt(grid.width)));
        const wy = @mod(sy + @as(f32, @floatFromInt(grid.height)), @as(f32, @floatFromInt(grid.height)));
        const ix = @as(usize, @intFromFloat(wx));
        const iy = @as(usize, @intFromFloat(wy));
        return grid.getFood(ix, iy);
    }
};

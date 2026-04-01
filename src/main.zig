const std = @import("std");
const rl = @import("raylib");
const Sim = @import("sim.zig").Sim;

pub fn main() !void {
    // GPA is Zig's general purpose allocator — tracks allocations and catches leaks
    // In a release build you'd swap this for a faster allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const WIDTH = 800;
    const HEIGHT = 800;

    // Initialize the sim — allocates grid and agents
    var sim = try Sim.init(allocator, WIDTH, HEIGHT);
    defer sim.deinit();

    // Diffuse buffer — separate allocation so decayAndDiffuse can double buffer
    const buffer = try allocator.alloc(f32, WIDTH * HEIGHT);
    defer allocator.free(buffer);

    // RNG for the step function's jitter
    var rng = std.rand.Xoshiro256.init(12345);

    // Open the window
    rl.initWindow(WIDTH, HEIGHT, "slime-mold-zig");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Pixel buffer — one u8 per pixel, grayscale, written to a raylib texture
    const pixels = try allocator.alloc(u8, WIDTH * HEIGHT * 4);
    defer allocator.free(pixels);

    // Create a texture we'll update every frame with the trail map
    // Textures live on the GPU — updating one each frame is fast
    var texture = rl.loadTextureFromImage(rl.genImageColor(WIDTH, HEIGHT, rl.Color.black));
    defer rl.unloadTexture(texture);

    // Main loop — runs until you close the window
    while (!rl.windowShouldClose()) {
        // Advance the simulation one tick
        sim.step(&rng);
        sim.decayAndDiffuse(buffer);

        // Convert trail map (f32 0-255) to RGBA pixels for the texture
        for (0..WIDTH * HEIGHT) |i| {
            const val: u8 = @intFromFloat(@min(sim.grid.cells[i], 255.0));
            pixels[i * 4 + 0] = val; // R
            pixels[i * 4 + 1] = val; // G
            pixels[i * 4 + 2] = val; // B
            pixels[i * 4 + 3] = 255; // A — fully opaque
        }

        // Push pixel data to the GPU texture
        rl.updateTexture(texture, pixels.ptr);

        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);
        rl.drawTexture(texture, 0, 0, rl.Color.white);
        rl.drawFPS(10, 10);
        rl.endDrawing();
    }
}
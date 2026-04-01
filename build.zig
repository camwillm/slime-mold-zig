const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Pull in the raylib-zig dependency we declared in build.zig.zon
    const raylib_dep = b.dependency("raylib_zig", .{
    .target = target,
    .optimize = optimize,
    .linux_display_backend = .X11,
});

    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    // Define our executable
    const exe = b.addExecutable(.{
        .name = "slime-mold-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link raylib into our executable
    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);

    b.installArtifact(exe);

    // This lets you run with `zig build run`
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the simulation");
    run_step.dependOn(&run_cmd.step);
}

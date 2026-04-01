const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const exe = b.addExecutable(.{
        .name = "slime",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.rdynamic = true;
    exe.entry = .disabled;

    // Install the .wasm into www/ so it's co-located with index.html for serving
    const install_wasm = b.addInstallFileWithDir(
        exe.getEmittedBin(),
        .{ .custom = "../www" },
        "slime.wasm",
    );
    b.getInstallStep().dependOn(&install_wasm.step);
}

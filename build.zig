const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .Debug });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });

    const exe = b.addExecutable(.{
        .name = "6502-emu",
        .root_module = mod,
        .linkage = .static,
    });

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);

    if (b.args) |args| {
        run.addArgs(args);
    }

    const run_step = b.step("run", "run app");
    run_step.dependOn(&run.step);
}

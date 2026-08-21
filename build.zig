const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .Debug });

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .strip = false,
    });

    const lib = b.addLibrary(.{
        .name = "6502-emu",
        .root_module = lib_mod,
        .linkage = .static,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{
            .name = "emu",
            .module = lib_mod,
        }},
    });

    exe_mod.linkLibrary(lib);

    const exe = b.addExecutable(.{
        .name = "6502-emu",
        .root_module = exe_mod,
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

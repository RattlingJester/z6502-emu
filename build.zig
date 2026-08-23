const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .Debug,
    });

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

    const unit_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = .Debug,
        .strip = false,
    });

    const unit_tests = b.addTest(.{
        .root_module = unit_tests_mod,
        .name = "tests",
    });

    const functional_test_mod = b.createModule(.{
        .root_source_file = b.path("src/func_test.zig"),
        .target = target,
        .optimize = .Debug,
        .strip = false,
        .imports = &.{.{
            .name = "emu",
            .module = lib_mod,
        }},
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

    const ftest_exe = b.addExecutable(.{
        .name = "ftest",
        .root_module = functional_test_mod,
        .linkage = .static,
    });

    b.installArtifact(exe);
    b.installArtifact(unit_tests);
    b.installArtifact(ftest_exe);

    const run = b.addRunArtifact(exe);
    const run_ftest = b.addRunArtifact(ftest_exe);

    if (b.args) |args| {
        run.addArgs(args);
    }

    const run_step = b.step("run", "run app");
    run_step.dependOn(&run.step);

    const run_ftest_step = b.step("ftest", "run functional test");
    run_ftest_step.dependOn(&run_ftest.step);
}

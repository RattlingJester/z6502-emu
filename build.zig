const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });

    const lib = b.addLibrary(.{
        .name = "6502-emu",
        .root_module = lib_mod,
        .linkage = .static,
    });

    const unit_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/tests.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{.{
            .name = "emu",
            .module = lib_mod,
        }},
    });

    const unit_tests = b.addTest(.{
        .root_module = unit_tests_mod,
        .name = "tests",
    });

    const functional_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/func_test.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{.{
            .name = "emu",
            .module = lib_mod,
        }},
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("examples/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{
            .name = "emu",
            .module = lib_mod,
        }},
    });

    const exe = b.addExecutable(.{
        .name = "6502-emu-example",
        .root_module = exe_mod,
        .linkage = .static,
    });

    const ftest_exe = b.addExecutable(.{
        .name = "ftest",
        .root_module = functional_test_mod,
        .linkage = .static,
    });

    b.installArtifact(lib);
    b.installArtifact(exe);
    b.installArtifact(unit_tests);
    b.installArtifact(ftest_exe);

    const run = b.addRunArtifact(exe);
    const run_ftest = b.addRunArtifact(ftest_exe);
    const run_utest = b.addRunArtifact(unit_tests);

    if (b.args) |args| {
        run.addArgs(args);
    }

    const run_step = b.step("run", "run app");
    run_step.dependOn(&run.step);

    const run_ftest_step = b.step("ftest", "run functional test");
    run_ftest_step.dependOn(&run_ftest.step);

    const run_utest_step = b.step("utest", "run unit tests");
    run_utest_step.dependOn(&run_utest.step);
}

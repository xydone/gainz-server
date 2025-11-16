pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("gainz_server", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const openapi_module = b.addModule("openapi-generator", .{
        .root_source_file = b.path("src/openapi.zig"),
        .target = target,
        .optimize = optimize,
    });

    const pg = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });

    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    const jwt = b.dependency("jwt", .{
        .target = target,
        .optimize = optimize,
    });
    const zdt = b.dependency("zdt", .{
        .target = target,
        .optimize = optimize,
    });

    module.addImport("pg", pg.module("pg"));
    module.addImport("httpz", httpz.module("httpz"));
    module.addImport("jwt", jwt.module("jwt"));
    module.addImport("zdt", zdt.module("zdt"));

    openapi_module.addImport("pg", pg.module("pg"));
    openapi_module.addImport("httpz", httpz.module("httpz"));
    openapi_module.addImport("jwt", jwt.module("jwt"));
    openapi_module.addImport("zdt", zdt.module("zdt"));

    const exe = b.addExecutable(.{
        .name = "gainz_server",
        .root_module = module,
    });
    exe.linkLibC();

    b.installArtifact(exe);

    const openapi_generator_exe = b.addExecutable(.{
        .name = "openapi-generator",
        .root_module = openapi_module,
    });
    openapi_generator_exe.linkLibC();

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    const exe_unit_tests = b.addTest(.{
        .root_module = module,
        .test_runner = .{ .path = b.path("src/tests/test_runner.zig"), .mode = .simple },
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Test code with custom test runner");
    test_step.dependOn(&run_exe_unit_tests.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const run_openapi_generator = b.addRunArtifact(openapi_generator_exe);

    const openapi_run_step = b.step("openapi", "Run OpenAPI generator");

    openapi_run_step.dependOn(&run_openapi_generator.step);
    run_step.dependOn(openapi_run_step);

    // add args
    if (b.args) |args| {
        run_cmd.addArgs(args);
        run_exe_unit_tests.addArgs(args);
    }
    const exe_check = b.addExecutable(.{
        .name = "gainz_server",
        .root_module = module,
    });
    const openapi_exe = b.addExecutable(.{
        .name = "openapi-generator",
        .root_module = openapi_module,
    });

    const check = b.step("check", "Check if gainz_server compiles");
    check.dependOn(&exe_check.step);
    check.dependOn(&openapi_exe.step);
    check.dependOn(&exe_unit_tests.step);
}

const std = @import("std");

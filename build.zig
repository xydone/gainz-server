const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("gainz_server", .{
        .root_source_file = b.path("src/main.zig"),
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
    module.addImport("pg", pg.module("pg"));
    module.addImport("httpz", httpz.module("httpz"));
    module.addImport("jwt", jwt.module("jwt"));

    const exe = b.addExecutable(.{
        .name = "gainz_server",
        .root_module = module,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_check = b.addExecutable(.{
        .name = "gainz_server",
        .root_module = module,
    });
    const check = b.step("check", "Check if gainz_server compiles");
    check.dependOn(&exe_check.step);
}

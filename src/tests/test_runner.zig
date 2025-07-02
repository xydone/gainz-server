//! Fork of https://gist.github.com/karlseguin/c6bea5b35e4e8d26af6f81c22cb5d76b

const std = @import("std");
const builtin = @import("builtin");
const Printer = @import("benchmark.zig").Printer;

const Allocator = std.mem.Allocator;

const BORDER = "=" ** 80;

// use in custom panic handler
var current_test: ?[]const u8 = null;

const Config = struct {
    verbose: bool,
    fail_first: bool,
    filter: ?[]const u8,

    pub fn init() Config {
        return Config{
            .verbose = false,
            .fail_first = false,
            .filter = null,
        };
    }
};

pub fn main() !void {
    var mem: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&mem);
    const printer = Printer.init();

    const allocator = fba.allocator();

    var config = Config.init();

    const process_args = try std.process.argsAlloc(allocator);
    for (process_args) |arg| {
        if (std.mem.eql(u8, arg, "--verbose")) config.verbose = true;
        if (std.mem.eql(u8, arg, "--fail-first")) config.fail_first = true;
        if (std.mem.startsWith(u8, arg, "--filter")) {
            var tokens = std.mem.tokenizeSequence(u8, arg, "=");
            //skip "--filter"
            _ = tokens.next();
            const filter = tokens.next() orelse return;
            config.filter = filter;
        }
    }

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;
    var setup_teardown: usize = 0;

    for (builtin.test_functions) |t| {
        if (isSetup(t)) {
            t.func() catch |err| {
                return err;
            };
        }
    }

    for (builtin.test_functions) |t| {
        if (isSetup(t) or isTeardown(t)) {
            setup_teardown += 1;
            continue;
        }

        const is_unnamed_test = isUnnamed(t);
        if (config.filter) |f| {
            if (!is_unnamed_test and std.mem.indexOf(u8, t.name, f) == null) {
                continue;
            }
        }

        std.testing.allocator_instance = .{};
        const result = t.func();

        if (std.testing.allocator_instance.deinit() == .leak) {
            leak += 1;
        }

        if (result) |_| {
            pass += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip += 1;
            },
            else => {
                fail += 1;
                if (@errorReturnTrace()) |trace| {
                    printer.status(.fail, "{s}\n", .{BORDER});
                    printer.status(.fail, "TRACE:\n", .{});
                    std.debug.dumpStackTrace(trace.*);
                    printer.status(.fail, "{s}\n", .{BORDER});
                }
                if (config.fail_first) {
                    break;
                }
            },
        }
    }

    for (builtin.test_functions) |t| {
        if (isTeardown(t)) {
            t.func() catch |err| {
                return err;
            };
        }
    }

    const total_tests = builtin.test_functions.len - setup_teardown;
    const total_tests_executed = pass + fail;
    const not_executed = total_tests - total_tests_executed;
    printer.status(.text, "{s: <15}: {d}\n", .{ "TOTAL EXECUTED", total_tests_executed });
    printer.status(.pass, "{s: <15}: {d}\n", .{ "PASS", pass });
    printer.status(.fail, "{s: <15}: {d}\n", .{ "FAILED", fail });
    if (not_executed > 0) printer.status(.fail, "{s: <15}: {d}\n", .{ "NOT EXECUTED", not_executed });

    std.posix.exit(if (fail == 0) 0 else 1);
}

pub const panic = std.debug.FullPanic(struct {
    pub fn panicFn(msg: []const u8, first_trace_addr: ?usize) noreturn {
        if (current_test) |ct| {
            std.debug.print("\x1b[31m{s}\npanic running \"{s}\"\n{s}\x1b[0m\n", .{ BORDER, ct, BORDER });
        }
        std.debug.defaultPanic(msg, first_trace_addr);
    }
}.panicFn);

fn isUnnamed(t: std.builtin.TestFn) bool {
    const marker = ".test_";
    const test_name = t.name;
    const index = std.mem.indexOf(u8, test_name, marker) orelse return false;
    _ = std.fmt.parseInt(u32, test_name[index + marker.len ..], 10) catch return false;
    return true;
}

fn isSetup(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:beforeAll");
}

fn isTeardown(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:afterAll");
}

fn isNotTimed(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:noTime");
}

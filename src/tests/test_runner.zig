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

const TestStats = struct {
    pass: u64,
    fail: u64,
    skip: u64,
    leak: u64,
    setup_teardown: u64,

    pub fn init() TestStats {
        return TestStats{
            .pass = 0,
            .fail = 0,
            .skip = 0,
            .leak = 0,
            .setup_teardown = 0,
        };
    }
};

const TestList = struct {
    test_functions: *std.ArrayList(std.builtin.TestFn),
    callback: *const fn (CallbackParams) anyerror!void,

    pub const CallbackType = enum { basic, @"test" };
    pub const CallbackParams = struct { t: std.builtin.TestFn, config: Config, printer: Printer, test_stats: *TestStats };

    pub fn init(allocator: std.mem.Allocator, callback_type: CallbackType) TestList {
        const list = allocator.create(std.ArrayList(std.builtin.TestFn)) catch @panic("cannot allocate arraylist");
        list.* = std.ArrayList(std.builtin.TestFn).init(allocator);
        return TestList{
            .test_functions = list,
            .callback = switch (callback_type) {
                .basic => basic_callback,
                .@"test" => test_callback,
            },
        };
    }

    pub fn deinit(self: TestList, allocator: std.mem.Allocator) void {
        self.test_functions.deinit();
        allocator.destroy(self.test_functions);
    }

    pub fn basic_callback(params: CallbackParams) !void {
        params.t.func() catch |err| {
            return err;
        };
    }
    pub fn test_callback(params: CallbackParams) !void {
        const is_unnamed_test = isUnnamed(params.t);
        if (params.config.filter) |f| {
            if (!is_unnamed_test and std.mem.indexOf(u8, params.t.name, f) == null) {
                // continue;
                return;
            }
        }

        std.testing.allocator_instance = .{};
        const result = params.t.func();

        if (std.testing.allocator_instance.deinit() == .leak) {
            params.test_stats.leak += 1;
        }

        if (result) |_| {
            params.test_stats.pass += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                params.test_stats.skip += 1;
            },
            else => {
                params.test_stats.fail += 1;
                if (@errorReturnTrace()) |trace| {
                    params.printer.status(.fail, "{s}\n", .{BORDER});
                    params.printer.status(.fail, "TRACE:\n", .{});
                    std.debug.dumpStackTrace(trace.*);
                    params.printer.status(.fail, "{s}\n", .{BORDER});
                }
            },
        }
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

    var test_stats = TestStats.init();

    const setup_queue = TestList.init(allocator, .basic);
    defer setup_queue.deinit(allocator);
    const teardown_queue = TestList.init(allocator, .basic);
    defer teardown_queue.deinit(allocator);
    const endpoint_queue = TestList.init(allocator, .@"test");
    defer endpoint_queue.deinit(allocator);
    const api_queue = TestList.init(allocator, .@"test");
    defer api_queue.deinit(allocator);

    for (builtin.test_functions) |t| {
        const name = makeNameFriendly(t.name);
        if (isEndpoint(name)) {
            try endpoint_queue.test_functions.append(t);
            continue;
        }
        if (isAPI(name)) {
            try api_queue.test_functions.append(t);
            continue;
        }
        if (isSetup(name)) {
            try setup_queue.test_functions.append(t);
            test_stats.setup_teardown += 1;
            continue;
        }
        if (isTeardown(name)) {
            try teardown_queue.test_functions.append(t);
            test_stats.setup_teardown += 1;
            continue;
        }
    }

    // Order is:
    // 1. Setup
    // 2. API
    // 3. Endpoint
    // 4. Teardown
    const test_run_order = [_]TestList{ setup_queue, api_queue, endpoint_queue, teardown_queue };
    for (test_run_order) |list| {
        for (list.test_functions.items) |t| {
            const params = TestList.CallbackParams{ .config = config, .printer = printer, .test_stats = &test_stats, .t = t };
            try list.callback(params);
        }
    }

    const total_tests = builtin.test_functions.len - test_stats.setup_teardown;
    const total_tests_executed = test_stats.pass + test_stats.fail;
    const not_executed = total_tests - total_tests_executed;
    printer.status(.text, "{s: <15}: {d}\n", .{ "TOTAL EXECUTED", total_tests_executed });
    printer.status(.pass, "{s: <15}: {d}\n", .{ "PASS", test_stats.pass });
    printer.status(.fail, "{s: <15}: {d}\n", .{ "FAILED", test_stats.fail });
    if (not_executed > 0) printer.status(.fail, "{s: <15}: {d}\n", .{ "NOT EXECUTED", not_executed });

    std.posix.exit(if (test_stats.fail == 0) 0 else 1);
}

pub const panic = std.debug.FullPanic(struct {
    pub fn panicFn(msg: []const u8, first_trace_addr: ?usize) noreturn {
        if (current_test) |ct| {
            std.debug.print("\x1b[31m{s}\npanic running \"{s}\"\n{s}\x1b[0m\n", .{ BORDER, ct, BORDER });
        }
        std.debug.defaultPanic(msg, first_trace_addr);
    }
}.panicFn);

fn makeNameFriendly(name: []const u8) []const u8 {
    var it = std.mem.splitScalar(u8, name, '.');
    while (it.next()) |value| {
        if (std.mem.eql(u8, value, "test")) {
            const rest = it.rest();
            return if (rest.len > 0) rest else name;
        }
    }
    return name;
}

fn isUnnamed(t: std.builtin.TestFn) bool {
    const marker = ".test_";
    const test_name = t.name;
    const index = std.mem.indexOf(u8, test_name, marker) orelse return false;
    _ = std.fmt.parseInt(u32, test_name[index + marker.len ..], 10) catch return false;
    return true;
}

fn isSetup(test_name: []const u8) bool {
    return std.mem.endsWith(u8, test_name, "tests:beforeAll");
}

fn isTeardown(test_name: []const u8) bool {
    return std.mem.endsWith(u8, test_name, "tests:afterAll");
}

fn isNotTimed(test_name: []const u8) bool {
    return std.mem.endsWith(u8, test_name, "tests:noTime");
}
fn isAPI(test_name: []const u8) bool {
    return std.mem.startsWith(u8, test_name, "API");
}
fn isEndpoint(test_name: []const u8) bool {
    return std.mem.startsWith(u8, test_name, "Endpoint");
}

fn runTest(
    t: std.builtin.TestFn,
    config: Config,
    printer: Printer,
    test_stats: *TestStats,
) !void {
    const is_unnamed_test = isUnnamed(t);
    if (config.filter) |f| {
        if (!is_unnamed_test and std.mem.indexOf(u8, t.name, f) == null) {
            // continue;
            return;
        }
    }

    std.testing.allocator_instance = .{};
    const result = t.func();

    if (std.testing.allocator_instance.deinit() == .leak) {
        test_stats.leak += 1;
    }

    if (result) |_| {
        test_stats.pass += 1;
    } else |err| switch (err) {
        error.SkipZigTest => {
            test_stats.skip += 1;
        },
        else => {
            test_stats.fail += 1;
            if (@errorReturnTrace()) |trace| {
                printer.status(.fail, "{s}\n", .{BORDER});
                printer.status(.fail, "TRACE:\n", .{});
                std.debug.dumpStackTrace(trace.*);
                printer.status(.fail, "{s}\n", .{BORDER});
            }
            if (config.fail_first) {
                // break;
            }
        },
    }
}

const std = @import("std");

name: []const u8,
timer: std.time.Timer,
status: Status,
err: ?anyerror = null,

const Benchmark = @This();

pub fn start(name: []const u8) Benchmark {
    return .{
        .name = name,
        .timer = std.time.Timer.start() catch @panic("Could not start timer."),
        .status = .pass,
    };
}

pub fn end(self: *Benchmark) void {
    const time = self.timer.lap();

    const printer = Printer.init();
    const ms = @as(f64, @floatFromInt(time)) / 1_000_000.0;
    switch (self.status) {
        .pass => {
            printer.status(self.status, "{s} ({d:.2}ms)\n", .{ self.name, ms });
        },
        .fail => {
            printer.status(.fail, "\"{s}\" - {s}\n", .{ self.name, @errorName(self.err.?) });
        },
        else => {},
    }
}

/// Meant to be called with an errdefer
pub fn fail(self: *Benchmark, err: anyerror) void {
    self.status = .fail;
    self.err = err;
}

pub const Printer = struct {
    out: std.fs.File.Writer,

    pub fn init() Printer {
        return .{
            .out = std.io.getStdErr().writer(),
        };
    }

    pub fn fmt(self: Printer, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.out, format, args) catch unreachable;
    }

    pub fn status(self: Printer, s: Status, comptime format: []const u8, args: anytype) void {
        const color = switch (s) {
            .pass => "\x1b[32m",
            .fail => "\x1b[31m",
            .skip => "\x1b[33m",
            else => "",
        };
        const out = self.out;
        out.writeAll(color) catch @panic("writeAll failed?!");
        std.fmt.format(out, format, args) catch @panic("std.fmt.format failed?!");
        self.fmt("\x1b[0m", .{});
    }
};

pub const Status = enum {
    pass,
    fail,
    skip,
    text,
};

DATABASE_HOST: []const u8,
DATABASE_USERNAME: []const u8,
DATABASE_NAME: []const u8,
DATABASE_PASSWORD: []const u8,
DATABASE_PORT: ?u16 = 5433,
JWT_SECRET: []const u8,
REDIS_PORT: ?u16 = 6379,
DATA_DIR: []const u8,
ADDRESS: []const u8 = "127.0.0.1",

const log = std.log.scoped(.env);
const Env = @This();

pub fn init(allocator: Allocator) !Env {
    const file_name = if (!builtin.is_test) ".env" else ".testing.env";
    var env_file = dotenv.init(allocator, file_name) catch return error.OutOfMemory;
    defer env_file.deinit();

    var env: Env = undefined;

    inline for (@typeInfo(Env).@"struct".fields) |field| loop: {
        const type_info = @typeInfo(field.type);
        const result = env_file.get(field.name) orelse {
            if (type_info == .optional) {
                @field(env, field.name) = field.defaultValue() orelse @compileError(std.fmt.comptimePrint("{} is an optional and must have a default value, it currently doesn't.", .{@typeName(field.type)}));
                break :loop;
            } else {
                log.err("The .env file is missing a \"{s}\" parameter, please add it and try again!", .{field.name});
                return error.MissingFields;
            }
        };
        const field_type = blk: {
            if (type_info == .optional) break :blk type_info.optional.child else break :blk field.type;
        };
        switch (field_type) {
            []const u8 => {
                @field(env, field.name) = allocator.dupe(u8, result) catch return error.OutOfMemory;
            },
            u16, u32, u64 => |T| {
                @field(env, field.name) = std.fmt.parseInt(T, result, 10) catch return error.CouldntParse;
            },
            else => @compileError(std.fmt.comptimePrint("{} is not supported!", .{@typeName(field_type)})),
        }
    }
    return env;
}

pub fn deinit(self: Env, allocator: Allocator) void {
    inline for (@typeInfo(Env).@"struct".fields) |field| {
        switch (field.type) {
            []const u8 => {
                allocator.free(@field(self, field.name));
            },
            else => {},
        }
    }
}

const dotenv = @import("util/dotenv.zig");

const Allocator = std.mem.Allocator;

const builtin = @import("builtin");
const std = @import("std");

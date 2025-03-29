const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");

const log = std.log.scoped(.user_model);

const UserErrors = error{UsernameNotUnique};

pub const User = struct {
    allocator: std.mem.Allocator,
    id: i32,
    display_name: []u8,
    username: []u8,
    pub fn create(database: *pg.Pool, allocator: std.mem.Allocator, request: rq.PostUser) anyerror!User {
        var conn = try database.acquire();
        defer conn.release();
        const hashed_password = try auth.hashPassword(allocator, request.password);
        defer allocator.free(hashed_password);

        var row = conn.row(SQL_STRINGS.create, .{ request.display_name, request.username, hashed_password }) catch |err| {
            if (conn.err) |pg_err| {
                try conn.readyForQuery();
                if (pg_err.isUnique()) {
                    return UserErrors.UsernameNotUnique;
                }
                log.err(
                    "Encountered PostgreSQL error: severity: {s} | code: {s} | failure: {s} | details: {?s} | hint: {?s}",
                    .{ pg_err.severity, pg_err.code, pg_err.message, pg_err.detail, pg_err.hint },
                );
            }
            return err;
        } orelse return error.UserInsertFailed;
        defer row.deinit() catch {};

        const id = row.get(i32, 0);
        const display_name = try allocator.dupe(u8, row.get([]u8, 1));
        const username = try allocator.dupe(u8, row.get([]u8, 2));

        return User{ .allocator = allocator, .id = id, .display_name = display_name, .username = username };
    }

    fn delete(database: *pg.Pool, user_id: i32) !void {
        var conn = try database.acquire();
        defer conn.release();

        _ = try conn.exec(SQL_STRINGS.delete, .{user_id});
    }

    pub fn deinit(self: *User) void {
        self.allocator.free(self.display_name);
        self.allocator.free(self.username);
    }

    pub fn format(
        self: User,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("User{ ");
        try writer.print(".id = {d}, .display_name = {s}", .{ self.id, self.display_name });
        try writer.writeAll(" }");
    }
};

const SQL_STRINGS = struct {
    pub const create = "INSERT INTO users (display_name, username, password) VALUES ($1,$2,$3) returning id,display_name,username";
    pub const delete = "DELETE FROM users WHERE id=$1";
};

// TESTS
const Tests = @import("../tests/tests.zig");

test "create user" {
    var test_env = Tests.test_env;

    const display_name = try std.fmt.allocPrint(test_env.allocator, "Testing display name", .{});
    defer test_env.allocator.free(display_name);
    const username = try std.fmt.allocPrint(test_env.allocator, "Testing username", .{});
    defer test_env.allocator.free(username);
    const password = try std.fmt.allocPrint(test_env.allocator, "Testing password", .{});
    defer test_env.allocator.free(password);
    const request = rq.PostUser{
        .display_name = display_name,
        .username = username,
        .password = password,
    };

    var response = try User.create(
        test_env.database,
        test_env.allocator,
        request,
    );
    defer response.deinit();

    try std.testing.expectEqualStrings("Testing display name", response.display_name);
    try std.testing.expectEqualStrings("Testing username", response.username);
}

test "attempt duplicate user" {
    var test_env = Tests.test_env;

    const display_name = try std.fmt.allocPrint(test_env.allocator, "Testing display name", .{});
    defer test_env.allocator.free(display_name);
    const username = try std.fmt.allocPrint(test_env.allocator, "Testing username", .{});
    defer test_env.allocator.free(username);
    const password = try std.fmt.allocPrint(test_env.allocator, "Testing password", .{});
    defer test_env.allocator.free(password);

    const request = rq.PostUser{
        .display_name = display_name,
        .username = username,
        .password = password,
    };
    var response = User.create(
        test_env.database,
        test_env.allocator,
        request,
    ) catch |err| {
        return try std.testing.expect(err == UserErrors.UsernameNotUnique);
    };
    defer response.deinit();
    return error.TestUnexpectedResult;
}

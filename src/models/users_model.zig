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
    pub fn deinit(self: *User) void {
        self.allocator.free(self.display_name);
        self.allocator.free(self.username);
    }
};
pub fn create(database: *pg.Pool, allocator: std.mem.Allocator, request: rq.PostUser) anyerror!User {
    var conn = try database.acquire();
    defer conn.release();
    const hashed_password = try auth.hashPassword(allocator, request.password);
    defer allocator.free(hashed_password);

    var row = conn.row(SQL_STRINGS.create, .{ request.display_name, request.username, hashed_password }) catch |err| {
        if (conn.err) |pg_err| {
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

pub fn delete(database: *pg.Pool, user_id: i32) !void {
    var conn = try database.acquire();
    defer conn.release();

    _ = try conn.exec(SQL_STRINGS.delete, .{user_id});
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

const SQL_STRINGS = struct {
    pub const create = "INSERT INTO users (display_name, username, password) VALUES ($1,$2,$3) returning id,display_name,username";
    pub const delete = "DELETE FROM users WHERE id=$1";
};

// TESTS
const Tests = @import("../tests/tests.zig");

test "API User | Create" {
    // SETUP
    const test_name = "API User | Create";
    const test_env = Tests.test_env;
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;

    const display_name = try std.fmt.allocPrint(allocator, "Display {s}", .{test_name});
    defer allocator.free(display_name);
    const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
    defer allocator.free(password);

    const request = rq.PostUser{
        .display_name = display_name,
        .username = test_name,
        .password = password,
    };

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        var response = create(
            test_env.database,
            allocator,
            request,
        ) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        std.testing.expectEqualStrings(test_name, response.username) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(display_name, response.display_name) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "API User | Duplicate" {
    // SETUP
    const test_name = "API User | Duplicate";
    const test_env = Tests.test_env;
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;

    const display_name = try std.fmt.allocPrint(allocator, "Display {s}", .{test_name});
    defer allocator.free(display_name);
    const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
    defer allocator.free(password);

    const request = rq.PostUser{
        .display_name = display_name,
        .username = test_name,
        .password = password,
    };
    var user = try create(
        test_env.database,
        allocator,
        request,
    );
    defer user.deinit();

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        if (create(test_env.database, allocator, request)) |*duplicate_user| {
            const usr = @constCast(duplicate_user);
            usr.deinit();
        } else |err| {
            std.testing.expectEqual(UserErrors.UsernameNotUnique, err) catch |inner_err| benchmark.fail(inner_err);
        }
    }
}

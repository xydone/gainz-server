const std = @import("std");

const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");

const log = std.log.scoped(.user_model);

const UserErrors = error{UsernameNotUnique};

pub const Create = struct {
    pub const Request = struct {
        display_name: []const u8,
        username: []const u8,
        password: []const u8,
    };
    pub const Response = struct {
        id: i32,
        display_name: []u8,
        username: []u8,
        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            allocator.free(self.display_name);
            allocator.free(self.username);
        }
    };
    pub const Errors = error{
        CannotCreate,
        UsernameNotUnique,
        HashingError,
        OutOfMemory,
    } || DatabaseErrors;
    pub fn call(database: *Pool, allocator: std.mem.Allocator, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const error_handler = ErrorHandler{ .conn = conn };

        const hashed_password = auth.hashPassword(allocator, request.password) catch return error.HashingError;
        defer allocator.free(hashed_password);
        var row = conn.row(query_string, .{ request.display_name, request.username, hashed_password }) catch |err| {
            const error_data = error_handler.handle(err);
            if (error_data) |data| {
                if (data.isUnique()) return UserErrors.UsernameNotUnique;
                ErrorHandler.printErr(data);
            }

            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer row.deinit() catch {};

        const id = row.get(i32, 0);
        const display_name = allocator.dupe(u8, row.get([]u8, 1)) catch return error.OutOfMemory;
        const username = allocator.dupe(u8, row.get([]u8, 2)) catch return error.OutOfMemory;

        return Response{
            .id = id,
            .display_name = display_name,
            .username = username,
        };
    }
    const query_string = "INSERT INTO users (display_name, username, password) VALUES ($1,$2,$3) returning id,display_name,username";
};

pub const Delete = struct {
    pub const Response = bool;
    pub const Errors = error{NoUser} || DatabaseErrors;
    pub fn call(database: *Pool, user_id: i32) Errors!void {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const error_handler = ErrorHandler{ .conn = conn };

        const rows = conn.exec(query_string, .{user_id}) catch |err| {
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.NoUser;
        } orelse return error.NoUser;
        if (rows != 1) return error.NoUser;
    }
    const query_string = "DELETE FROM users WHERE id=$1";
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

    const request = Create.Request{
        .display_name = display_name,
        .username = test_name,
        .password = password,
    };

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        var response = Create.call(
            test_env.database,
            allocator,
            request,
        ) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit(allocator);

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

    const request = Create.Request{
        .display_name = display_name,
        .username = test_name,
        .password = password,
    };
    var user = try Create.call(
        test_env.database,
        allocator,
        request,
    );
    defer user.deinit(allocator);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        if (Create.call(test_env.database, allocator, request)) |*duplicate_user| {
            const usr = @constCast(duplicate_user);
            usr.deinit(allocator);
        } else |err| {
            std.testing.expectEqual(UserErrors.UsernameNotUnique, err) catch |inner_err| benchmark.fail(inner_err);
        }
    }
}

test "API User | Delete" {
    // SETUP
    const test_name = "API User | Delete";
    const test_env = Tests.test_env;
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;

    const display_name = try std.fmt.allocPrint(allocator, "Display {s}", .{test_name});
    defer allocator.free(display_name);
    const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
    defer allocator.free(password);

    const request = Create.Request{
        .display_name = display_name,
        .username = test_name,
        .password = password,
    };

    const user = try Create.call(test_env.database, allocator, request);
    defer user.deinit(allocator);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        _ = Delete.call(
            test_env.database,
            user.id,
        ) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

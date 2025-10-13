const std = @import("std");

const Pool = @import("../../db.zig").Pool;
const DatabaseErrors = @import("../../db.zig").DatabaseErrors;
const ErrorHandler = @import("../../db.zig").ErrorHandler;

const Handler = @import("../../handler.zig");

const log = std.log.scoped(.category_model);

pub const Create = struct {
    pub const Request = struct {
        name: []const u8,
        description: ?[]const u8 = null,
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        created_by: i32,
        name: []const u8,
        description: ?[]const u8 = null,
    };
    pub const Errors = error{ CannotCreate, CannotParseResult } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var row = conn.row(query_string, .{ user_id, request.name, request.description }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);

            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer row.deinit() catch {};

        const response = row.to(Response, .{ .dupe = true }) catch return error.CannotParseResult;
        return response;
    }
    const query_string =
        \\INSERT INTO
        \\training.exercise_category (created_by, name, description)
        \\VALUES
        \\($1, $2, $3)
        \\RETURNING *;
    ;
};

pub const Get = struct {
    pub const Request = struct {
        name: []u8,
        description: ?[]u8 = null,
    };
    pub const Response = struct {
        id: i32,
        name: []u8,
        description: ?[]u8 = null,
    };
    pub const Errors = error{ CannotGet, CannotParseResult, OutOfMemory } || DatabaseErrors;
    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool) Errors![]Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var result = conn.queryOpts(query_string, .{user_id}, .{ .column_names = true }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);

            return error.CannotGet;
        };
        defer result.deinit();
        var response: std.ArrayList(Response) = .empty;
        defer response.deinit(allocator);

        while (result.next() catch return error.CannotGet) |row| {
            try response.append(allocator, row.to(Response, .{}) catch return error.CannotParseResult);
        }
        return response.toOwnedSlice(allocator) catch return error.OutOfMemory;
    }
    const query_string = "SELECT id,name, description FROM training.exercise_category WHERE created_by = $1";
};

const Tests = @import("../../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "API Exercise Category | Create" {
    const test_name = "API Exercise Category | Create";
    //SETUP
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    // TEST
    {
        const request = Create.Request{ .name = "Chest" };
        const response = try Create.call(setup.user.id, test_env.database, .{
            .name = "Chest",
        });
        try std.testing.expectEqual(request.description, response.description);
        try std.testing.expectEqualStrings(request.name, response.name);
    }
}

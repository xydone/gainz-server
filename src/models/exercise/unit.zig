const log = std.log.scoped(.unit_model);

pub const Create = struct {
    pub const Request = struct {
        amount: f64,
        unit: []const u8,
        multiplier: f64,
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        created_by: i32,
        amount: f64,
        unit: []const u8,
        multiplier: f64,
    };
    pub const Errors = error{ CannotCreate, CannotParseResult } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var row = conn.row(query_string, .{ user_id, request.amount, request.unit, request.multiplier }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer row.deinit() catch {};

        return row.to(Response, .{ .dupe = true }) catch return error.CannotParseResult;
    }

    const query_string =
        \\INSERT INTO
        \\training.exercise_unit (created_by, amount, unit, multiplier)
        \\VALUES
        \\($1, $2, $3, $4)
        \\RETURNING *
    ;
};

pub const GetAll = struct {
    pub const Request = struct {};
    pub const Response = struct {
        id: i32,
        created_at: i64,
        created_by: i32,
        amount: f64,
        unit: []const u8,
        multiplier: f64,
    };
    pub const Errors = error{
        CannotGet,
        CannotParseResult,
        OutOfMemory,
    } || DatabaseErrors;

    /// Caller must free
    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool) Errors![]Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var list: std.ArrayList(Response) = .empty;
        defer list.deinit(allocator);

        const result = conn.query(query_string, .{user_id}) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        };

        while (result.next() catch return error.CannotGet) |row| {
            list.append(allocator, row.to(Response, .{ .dupe = true }) catch return error.CannotParseResult) catch return error.OutOfMemory;
        }

        return list.toOwnedSlice(allocator);
    }

    const query_string =
        \\SELECT *
        \\FROM training.exercise_unit
        \\WHERE created_by = $1;
    ;
};

const Tests = @import("../../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "API Exercise Unit | Create" {
    const test_name = "API Exercise Unit | Create";
    //SETUP
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    // TEST
    {
        const request = Create.Request{ .amount = 1, .multiplier = 1, .unit = test_name ++ "'s unit" };
        const response = try Create.call(setup.user.id, test_env.database, request);

        try std.testing.expectEqual(setup.user.id, response.created_by);
        try std.testing.expectEqual(request.amount, response.amount);
        try std.testing.expectEqual(request.multiplier, response.multiplier);
        try std.testing.expectEqualStrings(request.unit, response.unit);
    }
}

test "API Exercise Unit | Get All" {
    const test_name = "API Exercise Unit | Get All";
    //SETUP
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const create_request = Create.Request{ .amount = 1, .multiplier = 1, .unit = test_name ++ "'s unit" };
    const create = try Create.call(setup.user.id, test_env.database, create_request);

    const created_units = [_]Create.Response{create};
    // TEST
    {
        const response_list = try GetAll.call(allocator, setup.user.id, test_env.database);
        defer allocator.free(response_list);

        try std.testing.expectEqual(created_units.len, response_list.len);

        for (response_list, created_units) |response, created| {
            try std.testing.expectEqual(setup.user.id, response.created_by);
            try std.testing.expectEqual(created.id, response.id);
            try std.testing.expectEqual(created.amount, response.amount);
            try std.testing.expectEqual(created.multiplier, response.multiplier);
            try std.testing.expectEqual(created.created_at, response.created_at);
            try std.testing.expectEqualStrings(created.unit, response.unit);
        }
    }
}

const std = @import("std");

const Pool = @import("../../db.zig").Pool;
const DatabaseErrors = @import("../../db.zig").DatabaseErrors;
const ErrorHandler = @import("../../db.zig").ErrorHandler;

const Handler = @import("../../handler.zig");

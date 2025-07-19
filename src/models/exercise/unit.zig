const std = @import("std");

const Pool = @import("../../db.zig").Pool;
const DatabaseErrors = @import("../../db.zig").DatabaseErrors;
const ErrorHandler = @import("../../db.zig").ErrorHandler;

const Handler = @import("../../handler.zig");

const log = std.log.scoped(.unit_model);

pub const Create = struct {
    pub const Request = struct {
        amount: f64,
        unit: []u8,
        multiplier: f64,
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        created_by: i32,
        amount: f64,
        unit: []u8,
        multiplier: f64,
    };
    pub const Errors = error{ CannotCreate, CannotParseResult } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        const row = conn.row(query_string, .{ user_id, request.amount, request.unit, request.multiplier }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;

        return row.to(Response, .{}) catch return error.CannotParseResult;
    }

    const query_string =
        \\INSERT INTO
        \\exercise_unit (created_by, amount, unit, multiplier)
        \\VALUES
        \\($1, $2, $3, $4)
        \\RETURNING *
    ;
};

const std = @import("std");

const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;

const Handler = @import("../handler.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.note_entry_model);

pub const Create = struct {
    pub const Request = struct {
        note_id: u32,
    };
    pub const Response = struct {
        id: i32,
        created_by: i32,
        note_id: i32,
    };

    pub const Errors = error{
        CannotCreate,
    } || DatabaseErrors;

    pub fn call(ctx: *Handler.RequestContext, request: Request) Errors!Response {
        var conn = ctx.app.db.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var row = conn.row(query_string, //
            .{ ctx.user_id.?, request.note_id }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer row.deinit() catch {};

        const id = row.get(i32, 0);
        const created_by = row.get(i32, 1);
        const note_id = row.get(i32, 2);

        return Response{ .id = id, .created_by = created_by, .note_id = note_id };
    }

    const query_string = "INSERT into note_entry (created_by, note_id) values ($1,$2) returning id,created_by,note_id";
};

pub const GetInRange = struct {
    pub const Request = struct {
        note_id: u32,
        /// datetime string (ex: 2024-01-01)
        range_start: []const u8,
        /// datetime string (ex: 2024-01-01)
        range_end: []const u8,
    };
    pub const Response = struct {
        id: i32,
        created_by: i32,
        note_id: i32,
        created_at: i64,
    };
    pub const Errors = error{
        CannotGet,
        OutOfMemory,
    } || DatabaseErrors;

    pub fn call(ctx: *Handler.RequestContext, request: Request) Errors![]Response {
        var conn = ctx.app.db.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var result = conn.query(query_string, //
            .{ ctx.user_id.?, request.note_id, request.range_start, request.range_end }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        };
        defer result.deinit();

        var response: std.ArrayList(Response) = .empty;

        while (result.next() catch return error.CannotGet) |row| {
            const id = row.get(i32, 0);
            const created_at = row.get(i64, 1);
            const note_id = row.get(i32, 2);
            const created_by = row.get(i32, 3);

            response.append(ctx.app.allocator, Response{ .id = id, .created_at = created_at, .note_id = note_id, .created_by = created_by }) catch return error.OutOfMemory;
        }

        return response.toOwnedSlice(ctx.app.allocator);
    }

    const query_string = "SELECT * FROM note_entry WHERE created_by=$1 AND note_id=$2 AND created_at >=$3 AND created_at<$4";
};

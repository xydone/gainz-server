const log = std.log.scoped(.note_model);

pub const Create = struct {
    pub const Request = struct {
        title: []const u8,
        description: ?[]const u8,
    };
    pub const Response = struct {
        id: i32,
        title: []const u8,
        description: []const u8,
    };
    pub const Errors = error{
        CannotCreate,
    } || DatabaseErrors;
    pub fn call(ctx: *Handler.RequestContext, request: Request) Errors!Response {
        var conn = ctx.app.db.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var row = conn.row(query_string, //
            .{ ctx.user_id.?, request.title, request.description }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer row.deinit() catch {};

        const id = row.get(i32, 0);
        const title = row.get([]u8, 1);
        const description = row.get([]u8, 2);

        return Response{ .id = id, .title = title, .description = description };
    }
    const query_string = "INSERT into notes (created_by, title, description) values ($1,$2,$3) returning id,title,description";
};

pub const Get = struct {
    pub const Request = struct {
        id: u32,
    };
    pub const Response = struct {
        id: i32,
        title: []const u8,
        description: []const u8,
    };
    pub const Errors = error{
        NotFound,
    } || DatabaseErrors;
    pub fn call(ctx: *Handler.RequestContext, request: Request) Errors!Response {
        var conn = ctx.app.db.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var row = conn.row(query_string, //
            .{ ctx.user_id.?, request.id }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.NotFound;
        } orelse return error.NotFound;
        defer row.deinit() catch {};

        const id = row.get(i32, 0);
        const title = row.get([]u8, 2);
        const description = row.get([]u8, 3);

        return Response{ .id = id, .title = title, .description = description };
    }
    const query_string = "SELECT * FROM notes WHERE created_by=$1 AND id=$2";
};

const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;

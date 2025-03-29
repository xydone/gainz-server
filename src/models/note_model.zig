const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.note_model);

pub fn create(ctx: *Handler.RequestContext, request: rq.PostNote) anyerror!rs.PostNote {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.create, //
        .{ ctx.user_id.?, request.title, request.description }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer row.?.deinit() catch {};

    const id = row.?.get(i32, 0);
    const title = row.?.get([]u8, 1);
    const description = row.?.get([]u8, 2);

    return rs.PostNote{ .id = id, .title = title, .description = description };
}

pub fn get(ctx: *Handler.RequestContext, request: rq.GetNote) anyerror!rs.GetNote {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.get, //
        .{ ctx.user_id.?, request.id }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;
    defer row.deinit() catch {};

    const id = row.get(i32, 0);
    const title = row.get([]u8, 2);
    const description = row.get([]u8, 3);

    return rs.GetNote{ .id = id, .title = title, .description = description };
}

const SQL_STRINGS = struct {
    pub const create = "INSERT into notes (created_by, title, description) values ($1,$2,$3) returning id,title,description";
    pub const get = "SELECT * FROM notes WHERE created_by=$1 AND id=$2";
};

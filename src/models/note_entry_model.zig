const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.note_entry_model);

pub fn create(ctx: *Handler.RequestContext, request: rq.PostNoteEntry) anyerror!rs.PostNoteEntry {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.create, //
        .{ ctx.user_id.?, request.note_id }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer row.?.deinit() catch {};

    const id = row.?.get(i32, 0);
    const created_by = row.?.get(i32, 1);
    const note_id = row.?.get(i32, 2);

    return rs.PostNoteEntry{ .id = id, .created_by = created_by, .note_id = note_id };
}

pub fn getInRange(ctx: *Handler.RequestContext, request: rq.GetNoteRange) anyerror![]rs.GetNoteEntry {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var result = conn.query(SQL_STRINGS.getInRange, //
        .{ ctx.user_id.?, request.note_id, request.range_start, request.range_end }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();

    var response: std.ArrayList(rs.GetNoteEntry) = .empty;

    while (try result.next()) |row| {
        const id = row.get(i32, 0);
        const created_at = row.get(i64, 1);
        const note_id = row.get(i32, 2);
        const created_by = row.get(i32, 3);

        try response.append(ctx.app.allocator, rs.GetNoteEntry{ .id = id, .created_at = created_at, .note_id = note_id, .created_by = created_by });
    }

    return response.toOwnedSlice(ctx.app.allocator);
}

const SQL_STRINGS = struct {
    pub const create = "INSERT into note_entry (created_by, note_id) values ($1,$2) returning id,created_by,note_id";
    pub const getInRange = "SELECT * FROM note_entry WHERE created_by=$1 AND note_id=$2 AND created_at >=$3 AND created_at<$4";
};

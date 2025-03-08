const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.goals_model);

pub fn create(ctx: *Handler.RequestContext, request: rq.PostGoal) anyerror!void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    _ = conn.exec(SQL_STRINGS.create, //
        .{ ctx.user_id, request.target, request.value }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
}

pub fn get(ctx: *Handler.RequestContext) anyerror!rs.GetGoals {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.get, //
        .{ctx.user_id}) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;
    defer row.deinit() catch {};
    const goals = row.get(?[]u8, 0) orelse return error.NoGoals;
    const parsed = try std.json.parseFromSlice(rs.GetGoals, ctx.app.allocator, goals, .{});
    return parsed.value;
}

pub const SQL_STRINGS = struct {
    pub const create = "insert into goals (created_by, target, value) values ($1,$2,$3)";
    pub const get =
        \\ SELECT jsonb_object_agg(target, value) AS goals
        \\ FROM (
        \\ SELECT DISTINCT ON (target) target, value
        \\ FROM goals
        \\ WHERE created_by = $1
        \\ ORDER BY target, id DESC
        \\ ) sub;
    ;
};

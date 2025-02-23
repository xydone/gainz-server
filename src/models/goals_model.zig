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
        .{ ctx.user_id, request.nutrient, request.value }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
}

pub fn get(ctx: *Handler.RequestContext) anyerror![]rs.GetGoals {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var result = conn.query(SQL_STRINGS.get, //
        .{ctx.user_id}) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();

    var response = std.ArrayList(rs.GetGoals).init(ctx.app.allocator);
    while (try result.next()) |row| {
        const id = row.get(i32, 0);
        const nutrient = row.get([]u8, 1);
        const value = row.get(f64, 2);
        try response.append(.{ .id = id, .nutrient = nutrient, .value = value });
    }

    return try response.toOwnedSlice();
}

pub const SQL_STRINGS = struct {
    pub const create = "insert into goals (created_by, nutrient, value) values ($1,$2,$3)";
    pub const get =
        \\ SELECT
        \\ id,
        \\ nutrient,
        \\ value
        \\ FROM
        \\ (
        \\ SELECT
        \\ id,
        \\ nutrient,
        \\ value,
        \\ ROW_NUMBER() OVER (
        \\ PARTITION BY
        \\ nutrient
        \\ ORDER BY
        \\ id DESC
        \\ ) AS rn
        \\ FROM
        \\ goals
        \\ WHERE
        \\ created_by = $1
        \\ ) AS ranked_data
        \\ WHERE
        \\ rn = 1;
    ;
};

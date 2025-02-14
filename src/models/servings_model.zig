const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");

const log = std.log.scoped(.servings_model);

pub fn create(ctx: *Handler.RequestContext, request: rq.PostServings) anyerror!rs.PostServing {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var result = conn.rowOpts(SQL_STRINGS.create, .{ ctx.user_id, request.food_id, request.amount, request.unit, request.multiplier }, .{}) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;

    const id = result.get(i32, 0);
    const amount = result.get(f64, 1);
    const unit = result.get([]u8, 2);
    const multiplier = result.get(f64, 3);

    return rs.PostServing{ .id = id, .amount = amount, .unit = try ctx.app.allocator.dupe(u8, unit), .multiplier = multiplier };
}

pub fn get(ctx: *Handler.RequestContext, request: rq.GetServings) anyerror![]rs.GetServing {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var result = conn.queryOpts(SQL_STRINGS.get, //
        .{request.food_id}, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(rs.GetServing).init(ctx.app.allocator);

    while (try result.next()) |row| {
        const id = row.get(i32, 0);
        const amount = row.get(f64, 3);
        const unit = row.get([]u8, 4);
        const multiplier = row.get(f64, 5);

        try response.append(rs.GetServing{ .id = id, .amount = amount, .unit = unit, .multiplier = multiplier });
    }
    return try response.toOwnedSlice();
}

pub const SQL_STRINGS = struct {
    pub const create = "INSERT INTO servings (created_by, food_id, amount, unit, multiplier) VALUES($1,$2,$3,$4,$5) RETURNING id, amount, unit, multiplier;";
    pub const get = "SELECT * from servings WHERE food_id=$1";
};

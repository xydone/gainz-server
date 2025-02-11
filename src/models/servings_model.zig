const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");

const log = std.log.scoped(.servings_model);

pub fn get(ctx: *Handler.RequestContext, request: rq.GetServings) anyerror![]rs.GetServing {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var result = conn.queryOpts("SELECT * from servings WHERE food_id=$1", //
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

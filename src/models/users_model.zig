const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");

const log = std.log.scoped(.user_model);

pub fn create(ctx: *Handler.RequestContext, request: rq.PostUser) anyerror!rs.PostUser {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    const hashed_password = try auth.hashPassword(ctx.app.allocator, request.password);
    var row = conn.row("insert into users (display_name, username, password) values ($1,$2,$3) returning id,display_name", .{ request.display_name, request.username, hashed_password }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    //NOTE: you must deinitialize rows or else query time balloons 10x
    defer row.?.deinit() catch {};
    const id = row.?.get(i32, 0);
    const dn = row.?.get([]u8, 1);

    const dupe = try ctx.app.allocator.dupe(u8, dn);

    return rs.PostUser{ .id = id, .display_name = dupe };
}

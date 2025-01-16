const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");

const log = std.log.scoped(.token_model);

const ACCESS_TOKEN_EXPIRY = 60 * 30;
const REFRESH_TOKEN_EXPIRY = 7 * 24 * 60 * 60;

pub fn create(ctx: *Handler.RequestContext, request: rq.PostAuth) anyerror!rs.CreateToken {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row("SELECT id, password,display_name FROM users WHERE username=$1;", //
        .{request.username}) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;
    defer row.deinit() catch {};
    const user_id = row.get(i32, 0);
    const hash = row.get([]u8, 1);
    const display_name = row.get([]u8, 2);
    const isValidPassword = try auth.verifyPassword(ctx.app.allocator, hash, request.password);
    const claims = auth.JWTClaims{ .user_id = user_id, .exp = std.time.timestamp() + ACCESS_TOKEN_EXPIRY };
    const access_token = if (isValidPassword) try auth.createJWT(ctx.app.allocator, claims, ctx.app.env.get("JWT_SECRET").?) else return error.NotFound;
    const refresh_token = try auth.createSessionToken(ctx.app.allocator);
    _ = try ctx.app.redis_client.setWithExpiry(try std.fmt.allocPrint(ctx.app.allocator, "{}", .{user_id}), refresh_token, REFRESH_TOKEN_EXPIRY);
    return rs.CreateToken{ .display_name = display_name, .access_token = access_token, .refresh_token = refresh_token, .expires_in = ACCESS_TOKEN_EXPIRY };
}

pub fn refresh(ctx: *Handler.RequestContext, request: rq.GetRefreshToken) anyerror!rs.RefreshToken {
    var buf: [1024]u8 = undefined;
    const key = try std.fmt.bufPrint(&buf, "{}", .{request.user_id});
    const result = ctx.app.redis_client.get(key) catch |err| switch (err) {
        error.KeyValuePairNotFound => return error.NotFound,
        else => return error.MiscError,
    };
    if (!std.mem.eql(u8, result, ctx.refresh_token.?)) return error.NotFound;
    const claims = auth.JWTClaims{ .user_id = request.user_id, .exp = std.time.timestamp() + ACCESS_TOKEN_EXPIRY };

    const access_token = try auth.createJWT(ctx.app.allocator, claims, ctx.app.env.get("JWT_SECRET").?);

    return rs.RefreshToken{ .access_token = access_token, .expires_in = ACCESS_TOKEN_EXPIRY, .refresh_token = ctx.refresh_token.? };
}

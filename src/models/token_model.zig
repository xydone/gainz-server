const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");

const log = std.log.scoped(.token_model);

const ACCESS_TOKEN_EXPIRY = 15 * 60;
const REFRESH_TOKEN_EXPIRY = 7 * 24 * 60 * 60;

pub fn create(ctx: *Handler.RequestContext, request: rq.PostAuth) anyerror!rs.CreateToken {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.create, //
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
    _ = try ctx.app.redis_client.setWithExpiry(refresh_token, try std.fmt.allocPrint(ctx.app.allocator, "{}", .{user_id}), REFRESH_TOKEN_EXPIRY);
    return rs.CreateToken{ .display_name = display_name, .access_token = access_token, .refresh_token = refresh_token, .expires_in = ACCESS_TOKEN_EXPIRY };
}

pub fn refresh(ctx: *Handler.RequestContext) anyerror!rs.RefreshToken {
    const result = ctx.app.redis_client.get(ctx.refresh_token.?) catch |err| switch (err) {
        error.KeyValuePairNotFound => return error.NotFound,
        else => return error.MiscError,
    };
    const number = try std.fmt.parseInt(i32, result, 10);
    const claims = auth.JWTClaims{ .user_id = number, .exp = std.time.timestamp() + ACCESS_TOKEN_EXPIRY };

    const access_token = try auth.createJWT(ctx.app.allocator, claims, ctx.app.env.get("JWT_SECRET").?);

    return rs.RefreshToken{ .access_token = access_token, .expires_in = ACCESS_TOKEN_EXPIRY, .refresh_token = ctx.refresh_token.? };
}

pub const SQL_STRINGS = struct {
    pub const create = "SELECT id, password,display_name FROM users WHERE username=$1;";
};

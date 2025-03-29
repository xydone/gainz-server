const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");
const Auth = @import("../models/auth_model.zig").Auth;

const log = std.log.scoped(.auth);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .refresh = true };
    router.*.post("/api/auth", createToken, .{});
    router.*.post("/api/auth/logout", invalidateToken, .{ .data = &RouteData });
    router.*.post("/api/auth/refresh", refreshToken, .{ .data = &RouteData });
}

pub fn createToken(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const jwt_secret = ctx.app.env.get("JWT_SECRET").?;
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const json = std.json.parseFromSliceLeaky(rq.PostAuth, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const create_props = Auth.CreateProps{
        .allocator = ctx.app.allocator,
        .database = ctx.app.db,
        .jwt_secret = jwt_secret,
        .redis_client = ctx.app.redis_client,
    };
    var result = Auth.create(create_props, json) catch |err| switch (err) {
        error.NotFound => {
            try rs.handleResponse(res, rs.ResponseError.unauthorized, null);
            return;
        },
        else => {
            log.err("Error caught: {s}", .{@errorName(err)});
            try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
            return;
        },
    };
    defer result.deinit();
    res.status = 200;

    const response = rs.CreateToken{
        .access_token = result.access_token,
        .expires_in = result.expires_in,
        .refresh_token = result.refresh_token,
    };
    try res.json(response, .{});
}

pub fn refreshToken(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const jwt_secret = ctx.app.env.get("JWT_SECRET").?;

    const refresh_props = Auth.RefreshProps{
        .allocator = ctx.app.allocator,
        .jwt_secret = jwt_secret,
        .redis_client = ctx.app.redis_client,
        .refresh_token = ctx.refresh_token.?,
    };
    var result = Auth.refresh(refresh_props) catch |err| switch (err) {
        error.NotFound => {
            try rs.handleResponse(res, rs.ResponseError.unauthorized, null);
            return;
        },
        else => {
            log.err("Error caught: {s}", .{@errorName(err)});
            try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
            return;
        },
    };
    defer result.deinit();
    res.status = 200;

    const response = rs.RefreshToken{ .access_token = result.access_token, .expires_in = result.expires_in, .refresh_token = result.refresh_token };
    try res.json(response, .{});
}

pub fn invalidateToken(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const invalidate_props = Auth.InvalidateProps{ .redis_client = ctx.app.redis_client, .refresh_token = ctx.refresh_token.? };
    const result = Auth.invalidate(invalidate_props) catch |err| {
        log.err("Error caught: {s}", .{@errorName(err)});
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    if (result == false) {
        try rs.handleResponse(res, rs.ResponseError.unauthorized, "No such active refresh token!");
        return;
    }
    res.status = 200;
}

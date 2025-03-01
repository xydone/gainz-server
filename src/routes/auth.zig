const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");
const AuthModel = @import("../models/auth_model.zig");

const log = std.log.scoped(.auth);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .refresh = true };
    router.*.post("/api/auth", createToken, .{});
    router.*.post("/api/auth/logout", invalidateToken, .{ .data = &RouteData });
    router.*.post("/api/auth/refresh", refreshToken, .{ .data = &RouteData });
}

pub fn createToken(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const token = std.json.parseFromSliceLeaky(rq.PostAuth, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const result = AuthModel.create(ctx, token) catch |err| switch (err) {
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
    res.status = 200;
    try res.json(result, .{});
}

pub fn refreshToken(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const result = AuthModel.refresh(ctx) catch |err| switch (err) {
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
    res.status = 200;
    try res.json(result, .{});
}

pub fn invalidateToken(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const result = AuthModel.invalidate(ctx) catch |err| {
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

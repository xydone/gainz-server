const std = @import("std");

const httpz = @import("httpz");

const db = @import("../db.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const types = @import("../types.zig");
const auth = @import("../util/auth.zig");

const log = std.log.scoped(.users);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .refresh = true };
    router.*.post("/api/auth", createToken, .{});
    router.*.post("/api/auth/refresh", refreshToken, .{ .data = &RouteData });
}

pub fn createToken(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const token = std.json.parseFromSlice(rq.CreateTokenRequest, ctx.app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body does not match requirements!";
            return;
        };
        const result = db.createToken(ctx, token.value) catch |err| switch (err) {
            error.NotFound => {
                res.status = 400;
                res.body = "Wrong username or password!";
                return;
            },
            else => {
                log.err("Error caught: {s}", .{@errorName(err)});
                //TODO: error handling later
                res.status = 500;
                res.body = "Error encountered";
                return;
            },
        };
        try res.json(result, .{});
        return;
    }
    res.status = 400;
    res.body = "Body missing!";
    return;
}

pub fn refreshToken(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const token = std.json.parseFromSlice(rq.RefreshTokenRequest, ctx.app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body does not match requirements!";
            return;
        };
        const result = db.refreshToken(ctx, token.value) catch |err| switch (err) {
            error.NotFound => {
                res.status = 400;
                res.body = "Authentication failed!";
                return;
            },
            else => {
                log.err("Error caught: {s}", .{@errorName(err)});
                //TODO: error handling later
                res.status = 500;
                res.body = "Error encountered";
                return;
            },
        };
        try res.json(result, .{});
        return;
    }
    res.status = 400;
    res.body = "Body missing!";
    return;
}

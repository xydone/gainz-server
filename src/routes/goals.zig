const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");
const Goals = @import("../models/goals_model.zig").Goals;

const log = std.log.scoped(.goals);

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/user/goals", createGoal, .{ .data = &RouteData });
    router.*.get("/api/user/goals", getGoals, .{ .data = &RouteData });
}

pub fn createGoal(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const json = std.json.parseFromSliceLeaky(rq.PostGoal, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, null);
        return;
    };
    const goal = Goals.create(ctx.user_id.?, ctx.app.db, json) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    _ = goal; // autofix
    res.status = 200;
}

pub fn getGoals(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix

    const response = Goals.get(ctx.app.allocator, ctx.user_id.?, ctx.app.db) catch |err| switch (err) {
        error.NoGoals => {
            try rs.handleResponse(res, rs.ResponseError.not_found, "The user has no goals entered!");
            return;
        },
        else => {
            try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
            return;
        },
    };
    defer response.deinit();

    res.status = 200;
    return res.json(response.value, .{});
}

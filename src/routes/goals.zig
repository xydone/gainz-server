const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");
const ResponseError = @import("../response.zig").ResponseError;
const handleResponse = @import("../response.zig").handleResponse;

const types = @import("../types.zig");
const Create = @import("../models/goals_model.zig").Create;
const Get = @import("../models/goals_model.zig").Get;

const log = std.log.scoped(.goals);

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/user/goals", createGoal, .{ .data = &RouteData });
    router.*.get("/api/user/goals", getGoals, .{ .data = &RouteData });
}

pub fn createGoal(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try handleResponse(res, ResponseError.body_missing, null);
        return;
    };
    const json = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try handleResponse(res, ResponseError.bad_request, null);
        return;
    };
    const goal = Create.call(ctx.user_id.?, ctx.app.db, json) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;

    try res.json(goal, .{});
}

pub fn getGoals(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const response = Get.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db) catch |err| switch (err) {
        error.NoGoals => {
            try handleResponse(res, ResponseError.not_found, "The user has no goals entered!");
            return;
        },
        else => {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        },
    };

    res.status = 200;
    return res.json(response, .{});
}

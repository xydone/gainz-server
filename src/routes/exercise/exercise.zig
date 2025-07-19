const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");
const rs = @import("../../response.zig");
const Create = @import("../../models/exercise/exercise.zig").Create;
const GetAll = @import("../../models/exercise/exercise.zig").GetAll;

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.get("/api/exercise/", getExercises, .{ .data = &RouteData });
    router.*.post("/api/exercise/", createExercise, .{ .data = &RouteData });
}

pub fn getExercises(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    var exercises = GetAll.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    defer exercises.deinit();
    res.status = 200;
    try res.json(exercises.list, .{});
}

pub fn createExercise(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const json = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const exercise = Create.call(ctx.user_id.?, ctx.app.db, json) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;

    return res.json(exercise, .{});
}

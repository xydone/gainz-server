const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");
const rq = @import("../../request.zig");
const rs = @import("../../response.zig");
const Workout = @import("../../models/exercise/workout.zig");

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/exercise/workout", createWorkout, .{ .data = &RouteData });
}

fn createWorkout(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const workout = std.json.parseFromSliceLeaky(rq.PostWorkout, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    Workout.create(ctx, workout) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
}

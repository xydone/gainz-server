const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");
const rq = @import("../../request.zig");
const rs = @import("../../response.zig");
const Exercise = @import("../../models/exercise/exercise.zig");

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/exercise/entry", createEntry, .{ .data = &RouteData });
}

pub fn createEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const exercise_entry = std.json.parseFromSliceLeaky(rq.PostExerciseEntry, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    Exercise.logExercise(ctx, exercise_entry) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
}

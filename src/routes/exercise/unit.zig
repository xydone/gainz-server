const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");
const rq = @import("../../request.zig");
const rs = @import("../../response.zig");
const Create = @import("../../models/exercise/unit.zig").Create;

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/exercise/unit", createUnit, .{ .data = &RouteData });
}

pub fn createUnit(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const unit = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const response = Create.call(ctx.user_id.?, ctx.app.db, unit) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;

    try res.json(response, .{});
}

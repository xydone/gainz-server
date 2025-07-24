const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");
const handleResponse = @import("../../response.zig").handleResponse;
const ResponseError = @import("../../response.zig").ResponseError;

const types = @import("../../types.zig");
const Create = @import("../../models/exercise/category.zig").Create;
const Get = @import("../../models/exercise/category.zig").Get;

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.get("/api/exercise/category", getCategories, .{ .data = &RouteData });
    router.*.post("/api/exercise/category", createCategory, .{ .data = &RouteData });
}

pub fn getCategories(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const categories = Get.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(categories, .{});
}

pub fn createCategory(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try handleResponse(res, ResponseError.body_missing, null);
        return;
    };
    const category = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try handleResponse(res, ResponseError.body_missing_fields, null);
        return;
    };
    _ = Create.call(ctx.user_id.?, ctx.app.db, category) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
}

const log = std.log.scoped(.users);

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/note", postNote, .{ .data = &RouteData });
    router.*.get("/api/note/:note_id", getNote, .{ .data = &RouteData });
}

pub fn getNote(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const note_id = std.fmt.parseInt(u32, req.param("note_id").?, 10) catch {
        try handleResponse(res, ResponseError.bad_request, "note_id not valid integer!");
        return;
    };
    const request = Get.Request{ .id = note_id };

    const result = Get.call(ctx, request) catch |err| switch (err) {
        error.NotFound => {
            try handleResponse(res, ResponseError.not_found, null);
            return;
        },
        else => {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        },
    };
    res.status = 200;
    try res.json(result, .{});
}

pub fn postNote(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try handleResponse(res, ResponseError.body_missing, null);
        return;
    };
    const note = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try handleResponse(res, ResponseError.body_missing_fields, null);
        return;
    };
    const result = Create.call(ctx, note) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

const std = @import("std");

const httpz = @import("httpz");

const Create = @import("../models/note_model.zig").Create;
const Get = @import("../models/note_model.zig").Get;
const Handler = @import("../handler.zig");
const handleResponse = @import("../response.zig").handleResponse;
const ResponseError = @import("../response.zig").ResponseError;

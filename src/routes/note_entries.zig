const log = std.log.scoped(.users);

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/user/notes", postNote, .{ .data = &RouteData });
    router.*.get("/api/user/notes", getNoteRange, .{ .data = &RouteData });
}

fn getNoteRange(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();

    const note_id_string = query.get("id") orelse {
        try handleResponse(res, ResponseError.bad_request, "Missing ?id= from request parameters!");
        return;
    };
    const note_id = try std.fmt.parseInt(u32, note_id_string, 10);
    const start = query.get("start") orelse {
        try handleResponse(res, ResponseError.bad_request, "Missing ?start= from request parameters!");
        return;
    };
    const end = query.get("end") orelse {
        try handleResponse(res, ResponseError.bad_request, "Missing ?end= from request parameters!");
        return;
    };
    const request: GetInRange.Request = .{ .note_id = note_id, .range_start = start, .range_end = end };
    const result = GetInRange.call(ctx, request) catch {
        try handleResponse(res, ResponseError.not_found, null);
        return;
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
    try res.json(result, .{});
}

const std = @import("std");

const httpz = @import("httpz");

const Create = @import("../models/note_entry_model.zig").Create;
const GetInRange = @import("../models/note_entry_model.zig").GetInRange;
const Handler = @import("../handler.zig");
const handleResponse = @import("../response.zig").handleResponse;
const ResponseError = @import("../response.zig").ResponseError;

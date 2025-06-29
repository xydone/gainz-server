const std = @import("std");

const httpz = @import("httpz");

const NoteModel = @import("../models/note_model.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");

const log = std.log.scoped(.users);

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/note", postNote, .{ .data = &RouteData });
    router.*.get("/api/note/:note_id", getNote, .{ .data = &RouteData });
}

pub fn getNote(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const note_id = std.fmt.parseInt(u32, req.param("note_id").?, 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "note_id not valid integer!");
        return;
    };
    const request = rq.GetNote{ .id = note_id };

    const result = NoteModel.get(ctx, request) catch |err| switch (err) {
        error.NotFound => {
            try rs.handleResponse(res, rs.ResponseError.not_found, null);
            return;
        },
        else => {
            try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
            return;
        },
    };
    res.status = 200;
    try res.json(result, .{});
}

pub fn postNote(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const note = std.json.parseFromSliceLeaky(rq.PostNote, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const result = NoteModel.create(ctx, note) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

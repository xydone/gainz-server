const std = @import("std");

const httpz = @import("httpz");

const NoteEntryModel = @import("../models/note_entry_model.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");

const log = std.log.scoped(.users);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/user/notes", postNote, .{ .data = &RouteData });
    router.*.get("/api/user/notes", getNoteRange, .{ .data = &RouteData });
}

fn getNoteRange(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();
    const note_id_string = query.get("id") orelse {
        res.status = 400;
        res.body = "Missing ?id= from request parameters!";
        return;
    };
    const note_id = try std.fmt.parseInt(u32, note_id_string, 10);
    const start = query.get("start") orelse {
        res.status = 400;
        res.body = "Missing ?start= from request parameters!";
        return;
    };
    const end = query.get("end") orelse {
        res.status = 400;
        res.body = "Missing ?end= from request parameters!";
        return;
    };
    const request: rq.GetNoteRange = .{ .note_id = note_id, .range_start = start, .range_end = end };
    const result = NoteEntryModel.getInRange(ctx, request) catch {
        res.status = 404;
        res.body = "Note or user not found!";
        return;
    };
    res.status = 200;
    try res.json(result, .{});
    return;
}

pub fn postNote(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const note = std.json.parseFromSliceLeaky(rq.PostNoteEntry, ctx.app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body does not match requirements!";
            return;
        };
        const result = NoteEntryModel.create(ctx, note) catch {
            //TODO: error handling later
            res.status = 500;
            res.body = "Error encountered";
            return;
        };
        try res.json(result, .{});
    }
}

const std = @import("std");

const httpz = @import("httpz");

const db = @import("../db.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.entry);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.get("/api/user/entry/:entry_id", getEntry, .{ .data = &RouteData });
    router.*.post("/api/user/entry", postEntry, .{ .data = &RouteData });
}

fn getEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const request: rq.GetEntryRequest = .{ .entry = try std.fmt.parseInt(i32, req.param("entry_id").?, 10), .user_id = ctx.user_id.? };

    const result = db.getEntry(ctx, request) catch {
        res.status = 404;
        res.body = "Entry or user not found!";
        return;
    };
    res.status = 200;
    try res.json(result, .{});
    return;
}

fn postEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const entry: ?std.json.Parsed(rq.EntryRequest) = std.json.parseFromSlice(rq.EntryRequest, ctx.app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body does not match requirements!";
            return;
        };
        const result = db.createEntry(ctx, entry.?.value) catch {
            //TODO: error handling later
            res.status = 500;
            res.body = "Error encountered";
            return;
        };
        res.status = 200;
        try res.json(result, .{});
        return;
    } else {
        res.status = 400;
        res.body = "No body found!";
        return;
    }
}

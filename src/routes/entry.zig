const std = @import("std");

const httpz = @import("httpz");

const db = @import("../db.zig");
const rq = @import("../request.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.entry);

pub fn init(router: *httpz.Router(*types.App, *const fn (*types.App, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    router.*.get("/api/user/entry", getEntry, .{});
    router.*.post("/api/user/entry", postEntry, .{});
}

fn getEntry(app: *types.App, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const request: ?std.json.Parsed(rq.GetEntryRequest) = std.json.parseFromSlice(rq.GetEntryRequest, app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body does not match requirements!";
            return;
        };

        const result = db.getEntry(app, request.?.value) catch {
            res.status = 404;
            res.body = "Entry or user not found!";
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

fn postEntry(app: *types.App, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const entry: ?std.json.Parsed(rq.EntryRequest) = std.json.parseFromSlice(rq.EntryRequest, app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body does not match requirements!";
            return;
        };
        const result = db.createEntry(app, entry.?.value) catch {
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

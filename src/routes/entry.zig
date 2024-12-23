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
    _ = req; // autofix
    _ = app; // autofix
    log.err("Endpoint not implemented!", .{});
    res.status = 204;
    res.body = "Endpoint not implemented yet!";
    return;
}

fn postEntry(app: *types.App, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const entry: ?std.json.Parsed(rq.EntryRequest) = std.json.parseFromSlice(rq.EntryRequest, app.allocator, body, .{}) catch {
            //handle return
            return;
        };
        const result = db.createEntry(app, entry.?.value) catch {
            //TODO: error handling later, catch |err| above to do it
            res.status = 409;
            res.body = "Error encountered";
            return;
        };
        res.status = 200;
        try res.json(result, .{});
        return;
    }
    res.status = 400;
    res.body = "No body found!";
    return;
}

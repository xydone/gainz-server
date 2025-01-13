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
    router.*.get("/api/user/entry", getEntryRange, .{ .data = &RouteData });
    router.*.post("/api/user/entry", postEntry, .{ .data = &RouteData });
}

fn getEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const entry_id = std.fmt.parseInt(u32, req.param("entry_id").?, 10) catch {
        res.status = 400;
        res.body = "Food ID not valid integer!";
        return;
    };
    const request: rq.GetEntry = .{ .entry = entry_id };

    const result = db.getEntry(ctx, request) catch {
        res.status = 404;
        res.body = "Entry or user not found!";
        return;
    };
    res.status = 200;
    try res.json(result, .{});
    return;
}

fn getEntryRange(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();
    // parsing the parameter and then turning the string request to an enum (probably slow?)
    const group_type = std.meta.stringToEnum(types.DatePart, query.get("group") orelse {
        res.status = 400;
        res.body = "Missing ?group= from request parameters!";
        return;
    }) orelse {
        //handle invalid enum type
        res.status = 400;
        res.body = "Invalid group type!";
        return;
    };
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
    const request: rq.GetEntryRange = .{ .group_type = group_type, .range_start = start, .range_end = end };
    const result = db.getEntryRange(ctx, request) catch {
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
        const entry = std.json.parseFromSliceLeaky(rq.PostEntry, ctx.app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body does not match requirements!";
            return;
        };
        const result = db.createEntry(ctx, entry) catch {
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

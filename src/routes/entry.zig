const std = @import("std");

const httpz = @import("httpz");

const EntryModel = @import("../models/entry_model.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.entry);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.get("/api/user/entry/:entry_id", getEntry, .{ .data = &RouteData });
    router.*.get("/api/user/entry/stats", getEntryStats, .{ .data = &RouteData });
    router.*.get("/api/user/entry", getEntryRange, .{ .data = &RouteData });
    router.*.post("/api/user/entry", postEntry, .{ .data = &RouteData });
}

fn getEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const entry_id = std.fmt.parseInt(u32, req.param("entry_id").?, 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, null);
        return;
    };
    const request: rq.GetEntry = .{ .entry = entry_id };

    const result = EntryModel.get(ctx, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

fn getEntryStats(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();

    // parsing the parameter and then turning the string request to an enum (probably slow?)
    const group_type = std.meta.stringToEnum(types.DatePart, query.get("group") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?group= from request parameters!");
        return;
    }) orelse {
        //handle invalid enum type
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Invalid group type!");
        return;
    };
    const start = query.get("start") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?start= from request parameters!");
        return;
    };
    const end = query.get("end") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?end= from request parameters!");
        return;
    };

    const request: rq.GetEntryStats = .{ .group_type = group_type, .range_start = start, .range_end = end };
    const result = EntryModel.getStats(ctx, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

fn getEntryRange(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();
    const start = query.get("start") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?start= from request parameters!");
        return;
    };
    const end = query.get("end") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?end= from request parameters!");
        return;
    };

    const request: rq.GetEntryRange = .{ .range_start = start, .range_end = end };
    const result = EntryModel.getInRange(ctx, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

fn postEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const entry = std.json.parseFromSliceLeaky(rq.PostEntry, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const result = EntryModel.create(ctx, entry) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

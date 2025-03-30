const std = @import("std");

const httpz = @import("httpz");

const Entry = @import("../models/entry_model.zig").Entry;
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.entry);
pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/user/entry", postEntry, .{ .data = &RouteData });
    router.*.get("/api/user/entry/:entry_id", getEntry, .{ .data = &RouteData });
    router.*.delete("/api/user/entry/:entry_id", deleteEntry, .{ .data = &RouteData });
    router.*.put("/api/user/entry/:entry_id", putEntry, .{ .data = &RouteData });
    router.*.get("/api/user/entry/recent", getRecent, .{ .data = &RouteData });
    router.*.get("/api/user/entry/stats", getEntryAverage, .{ .data = &RouteData });
    router.*.get("/api/user/entry/stats/detailed", getEntryStatsDetailed, .{ .data = &RouteData });
    router.*.get("/api/user/entry", getEntryRange, .{ .data = &RouteData });
}

fn getEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const entry_id = std.fmt.parseInt(u32, req.param("entry_id").?, 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, null);
        return;
    };
    const request: rq.GetEntry = .{ .entry = entry_id };

    const result = Entry.get(ctx.user_id.?, ctx.app.db, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    res.status = 200;

    const response = rs.GetEntry{
        .id = result.id,
        .amount = result.amount,
        .category = result.category,
        .created_at = result.created_at,
        .food_id = result.food_id,
        .serving_id = result.serving_id,
        .user_id = result.user_id,
    };
    try res.json(response, .{});
}

fn deleteEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const entry_id = std.fmt.parseInt(u32, req.param("entry_id").?, 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, null);
        return;
    };

    Entry.delete(ctx, rq.DeleteEntry{ .id = entry_id }) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, "Cannot find an entry with this ID.");
        return;
    };
    res.status = 200;
}

fn putEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const entry_id = std.fmt.parseInt(u32, req.param("entry_id").?, 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, null);
        return;
    };

    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };

    const entry = std.json.parseFromSliceLeaky(rq.EditEntry, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };

    Entry.edit(ctx, entry, entry_id) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, "Cannot find an entry with this ID.");
        return;
    };
    res.status = 200;
}

fn getRecent(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();

    const limit = std.fmt.parseInt(u32, query.get("limit") orelse "10", 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, null);
        return;
    };
    const request: rq.GetEntryRecent = .{ .limit = limit };

    const result = Entry.getRecent(ctx.app.allocator, ctx.user_id.?, ctx.app.db, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    res.status = 200;

    var response = std.ArrayList(rs.GetEntryRecent).init(ctx.app.allocator);
    for (result.list) |entry| {
        try response.append(rs.GetEntryRecent{
            .id = entry.id,
            .created_at = entry.created_at,
            .brand_name = entry.food.?.brand_name,
            .food_name = entry.food.?.food_name,
            .nutrients = entry.food.?.nutrients,
        });
    }
    try res.json(try response.toOwnedSlice(), .{});
}

fn getEntryAverage(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();

    const start = query.get("start") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?start= from request parameters!");
        return;
    };
    const end = query.get("end") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?end= from request parameters!");
        return;
    };

    const request: rq.GetEntryBreakdown = .{ .range_start = start, .range_end = end };
    const result = Entry.getAverage(ctx.user_id.?, ctx.app.db, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

fn getEntryStatsDetailed(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();
    const start = query.get("start") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?start= from request parameters!");
        return;
    };
    const end = query.get("end") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?end= from request parameters!");
        return;
    };

    const request: rq.GetEntryBreakdown = .{ .range_start = start, .range_end = end };
    const result = Entry.getBreakdown(ctx.app.allocator, ctx.user_id.?, ctx.app.db, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    res.status = 200;
    try res.json(result.list, .{});
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
    var result = Entry.getInRange(ctx.app.allocator, ctx.user_id.?, ctx.app.db, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    defer result.deinit();
    res.status = 200;

    var response = std.ArrayList(rs.GetEntryRange).init(ctx.app.allocator);
    for (result.list) |entry| {
        try response.append(rs.GetEntryRange{
            .entry_id = entry.id,
            .food_id = entry.food_id,
            .serving_id = entry.serving_id,
            .created_at = entry.created_at,
            .amount = entry.amount,
            .category = entry.category,
            .brand_name = entry.food.?.brand_name,
            .food_name = entry.food.?.food_name,
            .nutrients = entry.food.?.nutrients,
        });
    }
    try res.json(try response.toOwnedSlice(), .{});
}

fn postEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const json = std.json.parseFromSliceLeaky(rq.PostEntry, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const result = Entry.create(ctx.user_id.?, ctx.app.db, json) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };

    const response = rs.PostEntry{ .category = result.category, .food_id = result.food_id, .id = result.id, .user_id = result.user_id };
    res.status = 200;
    try res.json(response, .{});
}

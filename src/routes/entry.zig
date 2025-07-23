const std = @import("std");

const httpz = @import("httpz");

const Create = @import("../models/entry_model.zig").Create;
const Get = @import("../models/entry_model.zig").Get;
const Delete = @import("../models/entry_model.zig").Delete;
const Edit = @import("../models/entry_model.zig").Edit;
const GetAverage = @import("../models/entry_model.zig").GetAverage;
const GetBreakdown = @import("../models/entry_model.zig").GetBreakdown;
const GetInRange = @import("../models/entry_model.zig").GetInRange;
const GetRecent = @import("../models/entry_model.zig").GetRecent;

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.entry);
pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/user/entry", postEntry, .{ .data = &RouteData });
    router.*.get("/api/user/entry/:entry_id", getEntry, .{ .data = &RouteData });
    router.*.delete("/api/user/entry/:entry_id", deleteEntry, .{ .data = &RouteData });
    router.*.put("/api/user/entry/:entry_id", putEntry, .{ .data = &RouteData });
    router.*.get("/api/user/entry/recent", getEntryRecent, .{ .data = &RouteData });
    router.*.get("/api/user/entry/stats", getEntryAverage, .{ .data = &RouteData });
    router.*.get("/api/user/entry/stats/detailed", getEntryStatsDetailed, .{ .data = &RouteData });
    router.*.get("/api/user/entry", getEntryRange, .{ .data = &RouteData });
}

fn getEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const entry_id = std.fmt.parseInt(u32, req.param("entry_id").?, 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, null);
        return;
    };

    const result = Get.call(ctx.user_id.?, ctx.app.db, entry_id) catch {
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

    Delete.call(ctx.app.db, entry_id) catch {
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

    const entry = std.json.parseFromSliceLeaky(Edit.Request, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };

    Edit.call(ctx.app.db, entry, entry_id) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, "Cannot find an entry with this ID.");
        return;
    };
    res.status = 200;
}

fn getEntryRecent(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const allocator = ctx.app.allocator;
    const query = try req.query();

    const limit = std.fmt.parseInt(u32, query.get("limit") orelse "10", 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, null);
        return;
    };

    const result = GetRecent.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db, limit) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    defer {
        for (result) |entry| {
            entry.deinit(allocator);
        }
        allocator.free(result);
    }
    res.status = 200;

    try res.json(result, .{});
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

    const request: GetAverage.Request = .{ .range_start = start, .range_end = end };
    const result = GetAverage.call(ctx.user_id.?, ctx.app.db, request) catch {
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

    const request: GetBreakdown.Request = .{ .range_start = start, .range_end = end };
    const result = GetBreakdown.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

fn getEntryRange(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const allocator = ctx.app.allocator;

    const query = try req.query();
    const start = query.get("start") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?start= from request parameters!");
        return;
    };
    const end = query.get("end") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?end= from request parameters!");
        return;
    };

    const request: GetInRange.Request = .{ .range_start = start, .range_end = end };
    const result = GetInRange.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    defer allocator.free(result);
    res.status = 200;

    try res.json(result, .{});
}

fn postEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const json = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const result = Create.call(ctx.user_id.?, ctx.app.db, json) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };

    const response = rs.PostEntry{ .category = result.category, .food_id = result.food_id, .id = result.id, .user_id = result.user_id };
    res.status = 200;
    try res.json(response, .{});
}

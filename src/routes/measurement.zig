const std = @import("std");

const httpz = @import("httpz");

const get = @import("../models/measurements_model.zig").get;
const getInRange = @import("../models/measurements_model.zig").getInRange;
const getRecent = @import("../models/measurements_model.zig").getRecent;
const create = @import("../models/measurements_model.zig").create;

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.measurement);

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/user/measurement", postMeasurement, .{ .data = &RouteData });
    router.*.get("/api/user/measurement/", getMeasurementRange, .{ .data = &RouteData });
    router.*.get("/api/user/measurement/recent", getMeasurementRecent, .{ .data = &RouteData });
    router.*.get("/api/user/measurement/:measurement_id", getMeasurement, .{ .data = &RouteData });
}

fn getMeasurement(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const measurement_id = std.fmt.parseInt(u32, req.param("measurement_id").?, 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Measurement ID not valid integer!");
        return;
    };

    const value = rq.GetMeasurement{ .measurement_id = measurement_id };

    const result = get(ctx.user_id.?, ctx.app.db, value) catch |err| switch (err) {
        error.NotFound => {
            try rs.handleResponse(res, rs.ResponseError.unauthorized, null);
            return;
        },
        else => {
            try rs.handleResponse(res, rs.ResponseError.not_found, null);
            return;
        },
    };
    const response = rs.GetMeasurement{
        .created_at = result.created_at,
        .id = result.id,
        .type = result.type,
        .value = result.value,
    };
    try res.json(response, .{});
    return;
}

fn getMeasurementRange(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();
    // parsing the parameter and then turning the string request to an enum (probably slow?)
    const measurement_type = std.meta.stringToEnum(types.MeasurementType, query.get("type") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?type= from request parameters!");
        return;
    }) orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Invalid \'type\' field!");
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
    const request: rq.GetMeasurementRange = .{ .measurement_type = measurement_type, .range_start = start, .range_end = end };
    var measurements = getInRange(ctx.user_id.?, ctx.app.allocator, ctx.app.db, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    defer measurements.deinit();
    res.status = 200;
    try res.json(measurements.list, .{});
}

fn getMeasurementRecent(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();
    // parsing the parameter and then turning the string request to an enum (probably slow?)
    const measurement_type = std.meta.stringToEnum(types.MeasurementType, query.get("type") orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Missing ?type= from request parameters!");
        return;
    }) orelse {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Invalid \'type\' field!");
        return;
    };
    const request: rq.GetMeasurementRecent = .{ .measurement_type = measurement_type };
    const measurements = getRecent(ctx.user_id.?, ctx.app.db, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    res.status = 200;
    try res.json(measurements, .{});
}

fn postMeasurement(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const measurement = std.json.parseFromSliceLeaky(rq.PostMeasurement, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };

    const result = create(ctx.user_id.?, ctx.app.db, measurement) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    const response = rs.PostMeasurement{ .created_at = result.created_at, .type = result.type, .value = result.value };
    try res.json(response, .{});
}

const std = @import("std");

const httpz = @import("httpz");

const MeasurementModel = @import("../models/measurements_model.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.weight);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/user/measurement", postMeasurement, .{ .data = &RouteData });
    router.*.get("/api/user/measurement/", getMeasurementRange, .{ .data = &RouteData });
    router.*.get("/api/user/measurement/:measurement_id", getMeasurement, .{ .data = &RouteData });
}

fn getMeasurement(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const measurement_id = std.fmt.parseInt(u32, req.param("measurement_id").?, 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Measurement ID not valid integer!");
        return;
    };

    const value = rq.GetMeasurement{ .measurement_id = measurement_id };

    const result = MeasurementModel.get(ctx, value) catch |err| switch (err) {
        error.NotFound => {
            try rs.handleResponse(res, rs.ResponseError.unauthorized, null);
            return;
        },
        else => {
            try rs.handleResponse(res, rs.ResponseError.not_found, null);
            return;
        },
    };
    try res.json(result, .{});
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
    const result = MeasurementModel.getInRange(ctx, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
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

    const result = MeasurementModel.create(ctx, measurement) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

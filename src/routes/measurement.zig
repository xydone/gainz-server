const std = @import("std");

const httpz = @import("httpz");

const Get = @import("../models/measurements_model.zig").Get;
const GetInRange = @import("../models/measurements_model.zig").GetInRange;
const GetRecent = @import("../models/measurements_model.zig").GetRecent;
const Create = @import("../models/measurements_model.zig").Create;

const Handler = @import("../handler.zig");
const ResponseError = @import("../response.zig").ResponseError;
const handleResponse = @import("../response.zig").handleResponse;
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
        try handleResponse(res, ResponseError.bad_request, "Measurement ID not valid integer!");
        return;
    };

    const response = Get.call(ctx.user_id.?, ctx.app.db, measurement_id) catch |err| switch (err) {
        error.NotFound => {
            try handleResponse(res, ResponseError.unauthorized, null);
            return;
        },
        else => {
            try handleResponse(res, ResponseError.not_found, null);
            return;
        },
    };

    try res.json(response, .{});
    return;
}

fn getMeasurementRange(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const allocator = ctx.app.allocator;
    const query = try req.query();
    // parsing the parameter and then turning the string request to an enum (probably slow?)
    const measurement_type = std.meta.stringToEnum(types.MeasurementType, query.get("type") orelse {
        try handleResponse(res, ResponseError.bad_request, "Missing ?type= from request parameters!");
        return;
    }) orelse {
        try handleResponse(res, ResponseError.bad_request, "Invalid \'type\' field!");
        return;
    };
    const start = query.get("start") orelse {
        try handleResponse(res, ResponseError.bad_request, "Missing ?start= from request parameters!");
        return;
    };
    const end = query.get("end") orelse {
        try handleResponse(res, ResponseError.bad_request, "Missing ?end= from request parameters!");
        return;
    };
    const request: GetInRange.Request = .{ .range_start = start, .range_end = end };
    const measurements = GetInRange.call(ctx.user_id.?, ctx.app.allocator, ctx.app.db, measurement_type, request) catch {
        try handleResponse(res, ResponseError.not_found, null);
        return;
    };
    defer allocator.free(measurements);
    res.status = 200;
    try res.json(measurements, .{});
}

fn getMeasurementRecent(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();
    // parsing the parameter and then turning the string request to an enum (probably slow?)
    const measurement_type = std.meta.stringToEnum(types.MeasurementType, query.get("type") orelse {
        try handleResponse(res, ResponseError.bad_request, "Missing ?type= from request parameters!");
        return;
    }) orelse {
        try handleResponse(res, ResponseError.bad_request, "Invalid \'type\' field!");
        return;
    };
    const measurements = GetRecent.call(ctx.user_id.?, ctx.app.db, measurement_type) catch {
        try handleResponse(res, ResponseError.not_found, null);
        return;
    };
    res.status = 200;
    try res.json(measurements, .{});
}

fn postMeasurement(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try handleResponse(res, ResponseError.body_missing, null);
        return;
    };
    const measurement = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try handleResponse(res, ResponseError.body_missing_fields, null);
        return;
    };

    const result = Create.call(ctx.user_id.?, ctx.app.db, measurement) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

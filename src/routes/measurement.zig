const std = @import("std");

const httpz = @import("httpz");

const MeasurementModel = @import("../models/measurements_model.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
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
        res.status = 400;
        res.body = "Measurement ID not valid integer!";
        return;
    };

    const value = rq.GetMeasurement{ .measurement_id = measurement_id };

    const result = MeasurementModel.get(ctx, value) catch |err| switch (err) {
        error.NotFound => {
            //TODO: error handling later
            res.status = 401;
            res.body = "Not authorized to view this measurement!";
            return;
        },
        else => {
            //TODO: error handling later
            res.status = 500;
            res.body = "Error encountered";
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
        res.status = 400;
        res.body = "Missing ?type= from request parameters!";
        return;
    }) orelse {
        //handle invalid enum type
        res.status = 400;
        res.body = "Invalid 'type' type!";
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
    const request: rq.GetMeasurementRange = .{ .measurement_type = measurement_type, .range_start = start, .range_end = end };
    const result = MeasurementModel.getInRange(ctx, request) catch {
        res.status = 404;
        res.body = "Measurement or user not found!";
        return;
    };
    res.status = 200;
    try res.json(result, .{});
    return;
}

fn postMeasurement(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const measurement = std.json.parseFromSliceLeaky(rq.PostMeasurement, ctx.app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body does not match requirements!";
            return;
        };

        const result = MeasurementModel.create(ctx, measurement) catch {
            //TODO: error handling later
            res.status = 500;
            res.body = "Error encountered";
            return;
        };
        try res.json(result, .{});
        return;
    } else {
        //there is no body present
        //technically the else statement is not needed due to early return, but it is introduced so we can more easily debug when an early debug is not triggered
        res.status = 400;
        res.body = "Body not present!";
        return;
    }
}

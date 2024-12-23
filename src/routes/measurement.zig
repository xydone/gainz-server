const std = @import("std");

const httpz = @import("httpz");

const db = @import("../db.zig");
const rq = @import("../request.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.weight);

pub fn init(router: *httpz.Router(*types.App, *const fn (*types.App, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    router.*.get("/api/user/measurement", getMeasurement, .{});
    router.*.post("/api/user/measurement", postMeasurement, .{});
}

fn getMeasurement(app: *types.App, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    _ = app; // autofix
    log.err("Endpoint not implemented!", .{});
    res.status = 204;
    res.body = "Endpoint not implemented yet!";
    return;
}

fn postMeasurement(app: *types.App, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const measurement: std.json.Parsed(rq.MeasurementRequest) = std.json.parseFromSlice(rq.MeasurementRequest, app.allocator, body, .{}) catch {
            log.debug("JSON failed to parse!", .{});
            return;
        };

        const result = db.createMeasurement(app, measurement.value) catch {
            //TODO: error handling later, catch |err| above to do it
            res.status = 409;
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

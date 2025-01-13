const std = @import("std");

const httpz = @import("httpz");

const db = @import("../db.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.weight);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/user/measurement", postMeasurement, .{ .data = &RouteData });
}

fn postMeasurement(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const measurement = std.json.parseFromSliceLeaky(rq.MeasurementRequest, ctx.app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body does not match requirements!";
            return;
        };

        const result = db.createMeasurement(ctx, measurement) catch {
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

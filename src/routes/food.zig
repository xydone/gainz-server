const std = @import("std");

const httpz = @import("httpz");

const db = @import("../db.zig");
const rq = @import("../request.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.food);

pub fn init(router: *httpz.Router(*types.App, *const fn (*types.App, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    router.*.post("/api/food", postFood, .{});
}

// fn getFood(app: *types.App, req: *httpz.Request, res: *httpz.Response) void {
//     const self: *Self = @fieldParentPtr("ep", e);
// }

pub fn postFood(app: *types.App, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const food: ?std.json.Parsed(rq.FoodRequest) = std.json.parseFromSlice(rq.FoodRequest, app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body not properly formatted";
            return;
        };

        const result = db.createFood(app, food.?.value) catch {
            //TODO: error handling later, catch |err| above to do it
            res.status = 409;
            res.body = "Error encountered!";
            return;
        };
        //main return flow exit if body is present and valid
        res.status = 200;
        try res.json(result, .{});
        return;
    } else {
        res.status = 400;
        res.body = "Body missing!";
        return;
    }
}

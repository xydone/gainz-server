const std = @import("std");

const httpz = @import("httpz");

const db = @import("../db.zig");
const rq = @import("../request.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.food);

pub fn init(router: *httpz.Router(*types.App, *const fn (*types.App, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    router.*.get("/api/food", getFood, .{});
    router.*.get("/api/food/search/:search_term", searchFood, .{});
    router.*.get("/api/food/:id/servings", getServings, .{});
    router.*.post("/api/food", postFood, .{});
}

fn getFood(app: *types.App, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const request: std.json.Parsed(rq.GetFoodRequest) = std.json.parseFromSlice(rq.GetFoodRequest, app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body not properly formatted";
            return;
        };

        const result = db.getFood(app, request.value) catch {
            res.status = 404;
            res.body = "Food not found!";
            return;
        };
        res.status = 200;
        try res.json(result, .{});
        return;
    } else {
        res.status = 400;
        res.body = "Body missing!";
        return;
    }
}

pub fn postFood(app: *types.App, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const food: ?std.json.Parsed(rq.FoodRequest) = std.json.parseFromSlice(rq.FoodRequest, app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body not properly formatted";
            return;
        };

        const result = db.createFood(app, food.?.value) catch {
            //TODO: error handling later
            res.status = 500;
            res.body = "Error encountered";
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

pub fn searchFood(app: *types.App, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const request: rq.SearchFoodRequest = .{ .search_term = req.param("search_term").? };
    const result = db.searchFood(app, request) catch {
        //TODO: error handling later
        res.status = 500;
        res.body = "Error encountered";
        return;
    };
    res.status = 200;
    try res.json(result, .{});
    return;
}

pub fn getServings(app: *types.App, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const request: rq.GetServingsRequest = .{ .food_id = try std.fmt.parseInt(i32, req.param("id").?, 10) };
    const result = db.getServings(app, request) catch {
        //TODO: error handling later
        res.status = 500;
        res.body = "Error encountered";
        return;
    };
    res.status = 200;
    try res.json(result, .{});
    return;
}

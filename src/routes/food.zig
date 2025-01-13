const std = @import("std");

const httpz = @import("httpz");

const db = @import("../db.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.food);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };

    router.*.get("/api/food/:food_id", getFood, .{});
    router.*.get("/api/food", searchFood, .{});
    router.*.get("/api/food/:id/servings", getServings, .{});
    router.*.post("/api/food", postFood, .{ .data = &RouteData });
}

fn getFood(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const food_id = std.fmt.parseInt(u32, req.param("food_id").?, 10) catch {
        res.status = 400;
        res.body = "Food ID not valid integer!";
        return;
    };
    const request: rq.GetFood = .{ .food_id = food_id };

    const result = db.getFood(ctx, request) catch {
        res.status = 404;
        res.body = "Food not found!";
        return;
    };
    res.status = 200;
    try res.json(result, .{});
    return;
}

pub fn postFood(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const food = std.json.parseFromSliceLeaky(rq.PostFood, ctx.app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body not properly formatted";
            return;
        };

        const result = db.createFood(ctx, food) catch {
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

pub fn searchFood(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();
    var search_term: []const u8 = undefined;
    if (query.get("search")) |q| {
        search_term = q;
    } else {
        res.status = 400;
        res.body = "Search query missing!";
        return;
    }
    const request: rq.SearchFood = .{ .search_term = search_term };
    const result = db.searchFood(ctx, request) catch {
        //TODO: error handling later
        res.status = 500;
        res.body = "Error encountered";
        return;
    };
    res.status = 200;
    try res.json(result, .{});
    return;
}

pub fn getServings(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const request: rq.GetServings = .{ .food_id = try std.fmt.parseInt(i32, req.param("id").?, 10) };
    const result = db.getServings(ctx, request) catch {
        //TODO: error handling later
        res.status = 500;
        res.body = "Error encountered";
        return;
    };
    res.status = 200;
    try res.json(result, .{});
    return;
}

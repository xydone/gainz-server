const std = @import("std");

const httpz = @import("httpz");

const FoodModel = @import("../models/food_model.zig");
const ServingsModel = @import("../models/servings_model.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.food);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };

    router.*.get("/api/food/:food_id", getFood, .{ .data = &RouteData });
    router.*.get("/api/food", searchFood, .{ .data = &RouteData });
    router.*.get("/api/food/:id/servings", getServings, .{ .data = &RouteData });
    router.*.post("/api/food/:id/servings", postServings, .{ .data = &RouteData });
    router.*.post("/api/food", postFood, .{ .data = &RouteData });
}

fn getFood(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const food_id = std.fmt.parseInt(u32, req.param("food_id").?, 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Food ID not valid integer!");
        return;
    };
    const request: rq.GetFood = .{ .food_id = food_id };

    const result = FoodModel.get(ctx, request) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

pub fn postFood(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const food = std.json.parseFromSliceLeaky(rq.PostFood, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };

    FoodModel.create(ctx, food) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };

    res.status = 200;
}

pub fn searchFood(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();
    var search_term: []const u8 = undefined;
    if (query.get("search")) |q| {
        search_term = q;
    } else {
        try rs.handleResponse(res, rs.ResponseError.bad_request, null);
        return;
    }
    const request: rq.SearchFood = .{ .search_term = search_term };
    const result = FoodModel.search(ctx, request) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

pub fn postServings(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const food_id = try std.fmt.parseInt(i32, req.param("id").?, 10);
    if (food_id < 0) {
        try rs.handleResponse(res, rs.ResponseError.body_missing, "Food ID cannot be negative");
        return;
    }
    //the struct is rq.PostServings, but without food_id.
    //TODO: make this less ugly, preferably
    const ServingWithoutFoodId = struct { amount: f64, unit: []u8, multiplier: f64 };
    const request: ServingWithoutFoodId = std.json.parseFromSliceLeaky(ServingWithoutFoodId, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const result = ServingsModel.create(ctx, .{ .food_id = food_id, .amount = request.amount, .multiplier = request.multiplier, .unit = request.unit }) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

pub fn getServings(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const request: rq.GetServings = .{ .food_id = try std.fmt.parseInt(i32, req.param("id").?, 10) };
    const result = ServingsModel.get(ctx, request) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

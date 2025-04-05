const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");
const Exercise = @import("../models/exercise_model.zig").Exercise;
const Category = @import("../models/exercise_model.zig").Category;
const Unit = @import("../models/exercise_model.zig").Unit;

const log = std.log.scoped(.exercise);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    //exercises
    router.*.get("/api/exercise/", getExercises, .{ .data = &RouteData });
    router.*.post("/api/exercise/", createExercise, .{ .data = &RouteData });
    //categories
    router.*.get("/api/exercise/category", getCategories, .{ .data = &RouteData });
    router.*.post("/api/exercise/category", createCategory, .{ .data = &RouteData });
    //units
    router.*.post("/api/exercise/unit", createUnit, .{ .data = &RouteData });
    //entries
    router.*.post("/api/exercise/entry", createExerciseEntry, .{ .data = &RouteData });
}

pub fn getExercises(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    var exercises = Exercise.getAll(ctx.app.allocator, ctx.user_id.?, ctx.app.db) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    defer exercises.deinit();
    res.status = 200;
    try res.json(exercises.list, .{});
}

pub fn createExercise(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const json = std.json.parseFromSliceLeaky(rq.PostExercise, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const exercise = Exercise.create(ctx, json) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;

    return res.json(exercise, .{});
}

pub fn createCategory(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const category = std.json.parseFromSliceLeaky(rq.PostCategory, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    Category.create(ctx, category) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
}

pub fn createUnit(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const unit = std.json.parseFromSliceLeaky(rq.PostUnit, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    Unit.create(ctx, unit) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
}

pub fn createExerciseEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const exercise_entry = std.json.parseFromSliceLeaky(rq.PostExerciseEntry, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    Exercise.logExercise(ctx, exercise_entry) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
}

pub fn getCategories(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const categories = Category.get(ctx) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(categories, .{});
}

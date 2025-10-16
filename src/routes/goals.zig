const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");
const ResponseError = @import("../response.zig").ResponseError;
const handleResponse = @import("../response.zig").handleResponse;

const types = @import("../types.zig");
const Create = @import("../models/goals_model.zig").Create;
const GetActive = @import("../models/goals_model.zig").GetActive;
const GetAll = @import("../models/goals_model.zig").GetAll;

const log = std.log.scoped(.goals);

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/user/goals", createGoal, .{ .data = &RouteData });
    router.*.get("/api/user/goals", getAllGoals, .{ .data = &RouteData });
    router.*.get("/api/user/goals/active", getActiveGoals, .{ .data = &RouteData });
}

pub fn createGoal(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try handleResponse(res, ResponseError.body_missing, null);
        return;
    };
    const json = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try handleResponse(res, ResponseError.bad_request, null);
        return;
    };
    const goal = Create.call(ctx.user_id.?, ctx.app.db, json) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;

    try res.json(goal, .{});
}

pub fn getActiveGoals(ctx: *Handler.RequestContext, _: *httpz.Request, res: *httpz.Response) anyerror!void {
    const response = GetActive.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db) catch |err| switch (err) {
        error.NoGoals => {
            try handleResponse(res, ResponseError.not_found, "The user has no goals entered!");
            return;
        },
        else => {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        },
    };

    res.status = 200;
    return res.json(response, .{});
}

pub fn getAllGoals(ctx: *Handler.RequestContext, _: *httpz.Request, res: *httpz.Response) anyerror!void {
    const response = GetAll.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db) catch |err| switch (err) {
        error.NoGoals => {
            try handleResponse(res, ResponseError.not_found, "The user has no goals entered!");
            return;
        },
        else => {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        },
    };
    defer ctx.app.allocator.free(response);

    res.status = 200;
    return res.json(response, .{});
}

const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Endpoint Goals | Create" {
    // SETUP
    const test_name = "Endpoint Goals | Create";
    const ht = @import("httpz").testing;
    const jsonStringify = @import("../util/jsonStringify.zig").jsonStringify;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const body = Create.Request{
        .target = .weight,
        .value = 123.45,
    };

    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        try createGoal(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response: std.json.Parsed(Create.Response) = try std.json.parseFromSlice(Create.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expectEqual(response.value.target, body.target);
        try std.testing.expectEqual(response.value.value, body.value);
    }
}

test "Endpoint Goals | Get Active" {
    // SETUP
    const test_name = "Endpoint Goals | Get Active";
    const ht = @import("httpz").testing;
    const jsonStringify = @import("../util/jsonStringify.zig").jsonStringify;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const create_goal = Create.Request{
        .target = .weight,
        .value = 123.45,
    };

    const body_string = try jsonStringify(allocator, create_goal);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    _ = try Create.call(user.id, context.app.db, create_goal);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        try getActiveGoals(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response: std.json.Parsed(GetActive.Response) = try std.json.parseFromSlice(GetActive.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expectEqual(response.value.weight, create_goal.value);
    }
}

test "Endpoint Goals | Get All" {
    // SETUP
    const test_name = "Endpoint Goals | Get All";
    const ht = @import("httpz").testing;
    const jsonStringify = @import("../util/jsonStringify.zig").jsonStringify;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const create_goal = Create.Request{
        .target = .weight,
        .value = 123.45,
    };

    const created_goals = [_]Create.Request{create_goal};

    const body_string = try jsonStringify(allocator, create_goal);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    _ = try Create.call(user.id, context.app.db, create_goal);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        try getAllGoals(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const list: std.json.Parsed([]GetAll.Response) = try std.json.parseFromSlice([]GetAll.Response, allocator, response_body, .{});
        defer list.deinit();

        try std.testing.expectEqual(list.value.len, created_goals.len);

        for (list.value) |response| {
            try std.testing.expectEqual(response.target, create_goal.target);
            try std.testing.expectEqual(response.value, create_goal.value);
        }
    }
}

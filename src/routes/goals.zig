const log = std.log.scoped(.goals);

pub const endpoint_data = [_]EndpointData{
    Create.endpoint_data,
    GetActive.endpoint_data,
    GetAll.endpoint_data,
};

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Create.init(router);
    GetActive.init(router);
    GetAll.init(router);
}

const Create = Endpoint(struct {
    const Body = CreateModel.Request;

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = CreateModel.Response,
        .method = .POST,
        .path = "/api/user/goals",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const goal = CreateModel.call(ctx.user_id.?, ctx.app.db, request.body) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        res.status = 200;

        try res.json(goal, .{});
    }
});

const GetActive = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{},
        .Response = GetActiveModel.Response,
        .method = .GET,
        .path = "/api/user/goals/active",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, _: EndpointRequest(void, void, void), res: *httpz.Response) anyerror!void {
        const response = GetActiveModel.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db) catch |err| switch (err) {
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
});
const GetAll = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{},
        .Response = GetAllModel.Response,
        .method = .GET,
        .path = "/api/user/goals",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, _: EndpointRequest(void, void, void), res: *httpz.Response) anyerror!void {
        const response = GetAllModel.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db) catch |err| switch (err) {
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
});

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

    const body = CreateModel.Request{
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

        try Create.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response: std.json.Parsed(CreateModel.Response) = try std.json.parseFromSlice(CreateModel.Response, allocator, response_body, .{});
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

    const create_goal = CreateModel.Request{
        .target = .weight,
        .value = 123.45,
    };

    const body_string = try jsonStringify(allocator, create_goal);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    _ = try CreateModel.call(user.id, context.app.db, create_goal);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        try GetActive.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response: std.json.Parsed(GetActiveModel.Response) = try std.json.parseFromSlice(GetActiveModel.Response, allocator, response_body, .{});
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

    const create_goal = CreateModel.Request{
        .target = .weight,
        .value = 123.45,
    };

    const created_goals = [_]CreateModel.Request{create_goal};

    const body_string = try jsonStringify(allocator, create_goal);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    _ = try CreateModel.call(user.id, context.app.db, create_goal);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        try GetAll.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const list: std.json.Parsed([]GetAllModel.Response) = try std.json.parseFromSlice([]GetAllModel.Response, allocator, response_body, .{});
        defer list.deinit();

        try std.testing.expectEqual(list.value.len, created_goals.len);

        for (list.value) |response| {
            try std.testing.expectEqual(response.target, create_goal.target);
            try std.testing.expectEqual(response.value, create_goal.value);
        }
    }
}

const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");
const ResponseError = @import("../response.zig").ResponseError;
const handleResponse = @import("../response.zig").handleResponse;

const types = @import("../types.zig");
const CreateModel = @import("../models/goals_model.zig").Create;
const GetActiveModel = @import("../models/goals_model.zig").GetActive;
const GetAllModel = @import("../models/goals_model.zig").GetAll;

const Endpoint = @import("../handler.zig").Endpoint;
const EndpointRequest = @import("../handler.zig").EndpointRequest;
const EndpointData = @import("../handler.zig").EndpointData;

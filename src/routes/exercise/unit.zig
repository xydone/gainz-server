pub const endpoint_data = [_]EndpointData{
    Create.endpoint_data,
    GetAll.endpoint_data,
};

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Create.init(router);
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
        .path = "/api/exercise/unit",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const response = CreateModel.call(ctx.user_id.?, ctx.app.db, request.body) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        res.status = 200;

        try res.json(response, .{});
    }
});
const GetAll = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{},
        .Response = GetAllModel.Response,
        .method = .GET,
        .path = "/api/exercise/unit",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, _: EndpointRequest(void, void, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const response = GetAllModel.call(allocator, ctx.user_id.?, ctx.app.db) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        defer allocator.free(response);
        res.status = 200;

        try res.json(response, .{});
    }
});
const Tests = @import("../../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Endpoint Exercise Unit | Create" {
    // SETUP
    const test_name = "Endpoint Exercise Unit | Create";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const body = CreateModel.Request{ .amount = 1, .multiplier = 1, .unit = test_name ++ "'s unit" };
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
        const response = try std.json.parseFromSlice(CreateModel.Response, allocator, response_body, .{});
        defer response.deinit();

        const value = response.value;

        try std.testing.expectEqual(user.id, value.created_by);
        try std.testing.expectEqual(body.amount, value.amount);
        try std.testing.expectEqual(body.multiplier, value.multiplier);
        try std.testing.expectEqualStrings(body.unit, value.unit);
    }
}

test "Endpoint Exercise Unit | Get All" {
    // SETUP
    const test_name = "Endpoint Exercise Unit | Get All";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const create_request = CreateModel.Request{ .amount = 1, .multiplier = 1, .unit = test_name ++ "'s unit" };
    const create = try CreateModel.call(user.id, test_env.database, create_request);

    const created_list = [_]CreateModel.Response{create};

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        try GetAll.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]GetAllModel.Response, allocator, response_body, .{});
        defer response.deinit();

        for (response.value, created_list) |value, created| {
            try std.testing.expectEqual(user.id, value.created_by);
            try std.testing.expectEqual(created.amount, value.amount);
            try std.testing.expectEqual(created.multiplier, value.multiplier);
            try std.testing.expectEqualStrings(created.unit, value.unit);
        }
    }
}

const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");
const handleResponse = @import("../../response.zig").handleResponse;
const ResponseError = @import("../../response.zig").ResponseError;

const CreateModel = @import("../../models/exercise/unit.zig").Create;
const GetAllModel = @import("../../models/exercise/unit.zig").GetAll;

const jsonStringify = @import("../../util/jsonStringify.zig").jsonStringify;

const Endpoint = @import("../../handler.zig").Endpoint;
const EndpointRequest = @import("../../handler.zig").EndpointRequest;
const EndpointData = @import("../../handler.zig").EndpointData;

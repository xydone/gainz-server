const log = std.log.scoped(.auth);

const endpoint_list: []EndpointData = .{ Create.endpoint_data, Refresh.endpoint_data };

pub inline fn init(router: *Handler.Router) void {
    Create.init(router);
    Refresh.init(router);
}
const Create = Endpoint(struct {
    const Body = CreateModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = CreateModel.Response,
        .method = .POST,
        .config = .{},
        .path = "/api/auth",
        .route_data = .{},
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const jwt_secret = ctx.app.env.get("JWT_SECRET").?;

        const create_props = CreateModel.Props{
            .allocator = allocator,
            .database = ctx.app.db,
            .jwt_secret = jwt_secret,
            .redis_client = ctx.app.redis_client,
        };
        var response = CreateModel.call(create_props, request.body) catch |err| switch (err) {
            CreateModel.Errors.UserNotFound => {
                try handleResponse(res, ResponseError.unauthorized, null);
                return;
            },
            else => {
                log.err("Error caught: {s}", .{@errorName(err)});
                try handleResponse(res, ResponseError.internal_server_error, null);
                return;
            },
        };
        defer response.deinit(allocator);
        res.status = 200;

        try res.json(response, .{});
    }
});
const Refresh = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{},
        .Response = RefreshModel.Response,
        .method = .POST,
        .config = .{},
        .path = "/api/auth/refresh",
        .route_data = .{ .refresh = true },
    };
    pub fn call(ctx: *Handler.RequestContext, _: EndpointRequest(void, void, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const jwt_secret = ctx.app.env.get("JWT_SECRET").?;

        const refresh_props = RefreshModel.Props{
            .allocator = allocator,
            .jwt_secret = jwt_secret,
            .redis_client = ctx.app.redis_client,
            .refresh_token = ctx.refresh_token.?,
        };
        const response = RefreshModel.call(refresh_props) catch |err| switch (err) {
            RefreshModel.Errors.UserNotFound => {
                try handleResponse(res, ResponseError.unauthorized, null);
                return;
            },
            else => {
                log.err("Error caught: {s}", .{@errorName(err)});
                try handleResponse(res, ResponseError.internal_server_error, null);
                return;
            },
        };
        defer response.deinit(allocator);
        res.status = 200;

        try res.json(response, .{});
    }
});

const Invalidate = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{},
        .Response = RefreshModel.Response,
        .method = .POST,
        .config = .{},
        .path = "/api/auth/refresh",
        .route_data = .{ .refresh = true },
    };
    pub fn call(ctx: *Handler.RequestContext, _: EndpointRequest(void, void, void), res: *httpz.Response) anyerror!void {
        const invalidate_props = InvalidateModel.Props{
            .redis_client = ctx.app.redis_client,
            .refresh_token = ctx.refresh_token.?,
        };
        const result = InvalidateModel.call(invalidate_props) catch |err| {
            log.err("Error caught: {s}", .{@errorName(err)});
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        if (result == false) {
            try handleResponse(res, ResponseError.unauthorized, "No such active refresh token!");
            return;
        }
        res.status = 200;
    }
});

const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

// NOTE: only checks for 200 status
test "Endpoint Auth | Create" {
    // SETUP
    const test_name = "Endpoint Auth | Create";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    const user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const body = CreateModel.Request{
        .username = user.username,
        .password = "Testing password",
    };

    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(null, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        try Create.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
    }
}

test "Endpoint Auth | Refresh" {
    // SETUP
    const test_name = "Endpoint Auth | Refresh";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    const user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const body = CreateModel.Request{
        .username = user.username,
        .password = "Testing password",
    };

    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(null, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    // Create tokens
    var create_token_web = ht.init(.{});
    defer create_token_web.deinit();
    create_token_web.body(body_string);
    try Create.call(&context, create_token_web.req, create_token_web.res);

    const create_token_body = try create_token_web.getBody();

    const create_token_response = try std.json.parseFromSlice(CreateModel.Response, allocator, create_token_body, .{});
    defer create_token_response.deinit();

    context.refresh_token = create_token_response.value.refresh_token;

    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        try Refresh.call(&context, web_test.req, web_test.res);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(RefreshModel.Response, allocator, response_body, .{});
        defer response.deinit();

        try web_test.expectStatus(200);

        // The refresh tokens should be the same
        try std.testing.expectEqualStrings(create_token_response.value.refresh_token, response.value.refresh_token);
    }
}

const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");
const handleResponse = @import("../response.zig").handleResponse;
const ResponseError = @import("../response.zig").ResponseError;

const jsonStringify = @import("../util/jsonStringify.zig").jsonStringify;

const types = @import("../types.zig");
const CreateModel = @import("../models/auth_model.zig").Create;
const RefreshModel = @import("../models/auth_model.zig").Refresh;
const InvalidateModel = @import("../models/auth_model.zig").Invalidate;

const Endpoint = @import("../handler.zig").Endpoint;
const EndpointRequest = @import("../handler.zig").EndpointRequest;
const EndpointData = @import("../handler.zig").EndpointData;

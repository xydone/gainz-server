const log = std.log.scoped(.auth);

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .refresh = true };
    router.*.post("/api/auth", createToken, .{});
    router.*.post("/api/auth/logout", invalidateToken, .{ .data = &RouteData });
    router.*.post("/api/auth/refresh", refreshToken, .{ .data = &RouteData });
}

pub fn createToken(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const jwt_secret = ctx.app.env.get("JWT_SECRET").?;
    const body = req.body() orelse {
        try handleResponse(res, ResponseError.body_missing, null);
        return;
    };
    const json = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try handleResponse(res, ResponseError.body_missing_fields, null);
        return;
    };
    const create_props = Create.Props{
        .allocator = ctx.app.allocator,
        .database = ctx.app.db,
        .jwt_secret = jwt_secret,
        .redis_client = ctx.app.redis_client,
    };
    var response = Create.call(create_props, json) catch |err| switch (err) {
        Create.Errors.UserNotFound => {
            try handleResponse(res, ResponseError.unauthorized, null);
            return;
        },
        else => {
            log.err("Error caught: {s}", .{@errorName(err)});
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        },
    };
    defer response.deinit(ctx.app.allocator);
    res.status = 200;

    try res.json(response, .{});
}

pub fn refreshToken(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const jwt_secret = ctx.app.env.get("JWT_SECRET").?;

    const refresh_props = Refresh.Props{
        .allocator = ctx.app.allocator,
        .jwt_secret = jwt_secret,
        .redis_client = ctx.app.redis_client,
        .refresh_token = ctx.refresh_token.?,
    };
    const response = Refresh.call(refresh_props) catch |err| switch (err) {
        Refresh.Errors.UserNotFound => {
            try handleResponse(res, ResponseError.unauthorized, null);
            return;
        },
        else => {
            log.err("Error caught: {s}", .{@errorName(err)});
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        },
    };
    defer response.deinit(ctx.app.allocator);
    res.status = 200;

    try res.json(response, .{});
}

pub fn invalidateToken(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const invalidate_props = Auth.InvalidateProps{ .redis_client = ctx.app.redis_client, .refresh_token = ctx.refresh_token.? };
    const result = Auth.invalidate(invalidate_props) catch |err| {
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

    const body = Create.Request{
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

        try createToken(&context, web_test.req, web_test.res);
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

    const body = Create.Request{
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
    try createToken(&context, create_token_web.req, create_token_web.res);

    const create_token_body = try create_token_web.getBody();

    const create_token_response = try std.json.parseFromSlice(Create.Response, allocator, create_token_body, .{});
    defer create_token_response.deinit();

    context.refresh_token = create_token_response.value.refresh_token;

    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        try refreshToken(&context, web_test.req, web_test.res);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(Refresh.Response, allocator, response_body, .{});
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
const Auth = @import("../models/auth_model.zig").Auth;
const Create = @import("../models/auth_model.zig").Create;
const Refresh = @import("../models/auth_model.zig").Refresh;

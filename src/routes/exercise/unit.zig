pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/exercise/unit", createUnit, .{ .data = &RouteData });
    router.*.get("/api/exercise/unit", getUnits, .{ .data = &RouteData });
}

pub fn createUnit(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try handleResponse(res, ResponseError.body_missing, null);
        return;
    };
    const unit = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try handleResponse(res, ResponseError.body_missing_fields, null);
        return;
    };
    const response = Create.call(ctx.user_id.?, ctx.app.db, unit) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;

    try res.json(response, .{});
}

pub fn getUnits(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const allocator = ctx.app.allocator;
    const response = GetAll.call(allocator, ctx.user_id.?, ctx.app.db) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    defer allocator.free(response);
    res.status = 200;

    try res.json(response, .{});
}
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

    const body = Create.Request{ .amount = 1, .multiplier = 1, .unit = test_name ++ "'s unit" };
    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        try createUnit(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(Create.Response, allocator, response_body, .{});
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

    const create_request = Create.Request{ .amount = 1, .multiplier = 1, .unit = test_name ++ "'s unit" };
    const create = try Create.call(user.id, test_env.database, create_request);

    const created_list = [_]Create.Response{create};

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        try getUnits(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]GetAll.Response, allocator, response_body, .{});
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

const Create = @import("../../models/exercise/unit.zig").Create;
const GetAll = @import("../../models/exercise/unit.zig").GetAll;

const jsonStringify = @import("../../util/jsonStringify.zig").jsonStringify;

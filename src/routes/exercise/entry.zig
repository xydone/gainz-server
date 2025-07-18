const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");
const rs = @import("../../response.zig");
const LogExercise = @import("../../models/exercise/exercise.zig").LogExercise;

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/exercise/entry", createEntry, .{ .data = &RouteData });
}

pub fn createEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const exercise_entry = std.json.parseFromSliceLeaky(LogExercise.Request, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const response = LogExercise.call(ctx.user_id.?, ctx.app.db, exercise_entry) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;

    try res.json(response, .{});
}

const Tests = @import("../../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Endpoint Exercise | Log" {
    // SETUP
    const test_name = "Endpoint Exercise | Log";
    const ht = @import("httpz").testing;
    const Create = @import("../../models/exercise/exercise.zig").Create;
    const CreateCategory = @import("../../models/exercise/category.zig").Create;
    const Benchmark = @import("../../tests/test_runner.zig").Benchmark;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const category_request = CreateCategory.Request{ .name = "Chest" };

    const category = try CreateCategory.call(user.id, test_env.database, category_request);

    const create_request = Create.Request{
        .name = test_name ++ " exercise",
        .base_amount = 1,
        .base_unit = test_name ++ "'s plates",
        .category_id = @intCast(category.id),
    };

    const exercise = try Create.call(user.id, test_env.database, create_request);

    const body = LogExercise.Request{
        .exercise_id = @intCast(exercise.id),
        .unit_id = @intCast(exercise.base_unit_id),
        .value = 123,
    };
    const body_string = try std.json.stringifyAlloc(allocator, body, .{});
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        createEntry(&context, web_test.req, web_test.res) catch |err| {
            benchmark.fail(err);
            return err;
        };
        web_test.expectStatus(200) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response_body = web_test.getBody() catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response = std.json.parseFromSlice(LogExercise.Response, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        std.testing.expectEqual(user.id, response.value.created_by) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(exercise.base_unit_id, response.value.unit_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(exercise.id, response.value.exercise_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(body.value, response.value.value) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

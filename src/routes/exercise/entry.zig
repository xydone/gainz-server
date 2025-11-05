pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.post("/api/exercise/entry", createEntry, .{ .data = &RouteData });
    router.*.put("/api/exercise/entry/:entry_id", editEntry, .{ .data = &RouteData });
    router.*.delete("/api/exercise/entry/:entry_id", deleteEntry, .{ .data = &RouteData });
    router.*.get("/api/exercise/entry/range", getExerciseEntryRange, .{ .data = &RouteData });
}

pub fn createEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try handleResponse(res, ResponseError.body_missing, null);
        return;
    };
    const exercise_entry = std.json.parseFromSliceLeaky(LogExercise.Request, ctx.app.allocator, body, .{}) catch {
        try handleResponse(res, ResponseError.body_missing_fields, null);
        return;
    };
    const response = LogExercise.call(ctx.user_id.?, ctx.app.db, exercise_entry) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;

    try res.json(response, .{});
}

pub fn editEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const entry_id = std.fmt.parseInt(u32, req.param("entry_id").?, 10) catch {
        try handleResponse(res, ResponseError.bad_request, null);
        return;
    };
    const body = req.body() orelse {
        try handleResponse(res, ResponseError.body_missing, null);
        return;
    };
    const exercise_entry = std.json.parseFromSliceLeaky(EditExerciseEntry.Request, ctx.app.allocator, body, .{}) catch {
        try handleResponse(res, ResponseError.body_missing_fields, null);
        return;
    };
    if (!exercise_entry.isValid()) {
        try handleResponse(res, ResponseError.body_missing_fields, "Request body must contain at least one of the optional values");
        return;
    }
    const response = EditExerciseEntry.call(ctx.user_id.?, entry_id, ctx.app.db, exercise_entry) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;

    try res.json(response, .{});
}

pub fn deleteEntry(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const entry_id = std.fmt.parseInt(u32, req.param("entry_id").?, 10) catch {
        try handleResponse(res, ResponseError.bad_request, null);
        return;
    };
    const response = DeleteExerciseEntry.call(ctx.user_id.?, ctx.app.db, entry_id) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;

    try res.json(response, .{});
}

pub fn getExerciseEntryRange(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();
    const start = query.get("start") orelse {
        try handleResponse(res, ResponseError.bad_request, "Missing ?start= from request parameters!");
        return;
    };
    const end = query.get("end") orelse {
        try handleResponse(res, ResponseError.bad_request, "Missing ?end= from request parameters!");
        return;
    };
    const request: GetRange.Request = .{ .range_start = start, .range_end = end };

    var exercises = GetRange.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db, request) catch |err| {
        switch (err) {
            error.NoEntriesFound => try handleResponse(res, ResponseError.not_found, "No exercise entries found in the given range!"),
            else => try handleResponse(res, ResponseError.internal_server_error, null),
        }
        return;
    };
    defer exercises.deinit();

    res.status = 200;
    try res.json(exercises.list, .{});
}

const Tests = @import("../../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Endpoint Exercise | Log Entry" {
    // SETUP
    const test_name = "Endpoint Exercise | Log Entry";
    const ht = @import("httpz").testing;
    const Create = @import("../../models/exercise/exercise.zig").Create;
    const CreateCategory = @import("../../models/exercise/category.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const category_request = CreateCategory.Request{ .name = "Chest" };

    const category = try CreateCategory.call(user.id, test_env.database, category_request);

    var category_ids = [_]i32{category.id};
    const create_request = Create.Request{
        .name = test_name ++ " exercise",
        .base_amount = 1,
        .base_unit = test_name ++ "'s plates",
        .category_ids = &category_ids,
    };

    const exercise = try Create.call(user.id, test_env.database, create_request);

    const body = LogExercise.Request{
        .exercise_id = @intCast(exercise.id),
        .unit_id = @intCast(exercise.base_unit_id),
        .value = 123,
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

        try createEntry(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(LogExercise.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expectEqual(user.id, response.value.created_by);
        try std.testing.expectEqual(exercise.base_unit_id, response.value.unit_id);
        try std.testing.expectEqual(exercise.id, response.value.exercise_id);
        try std.testing.expectEqual(body.value, response.value.value);
    }
}

test "Endpoint Exercise | Edit Entry" {
    // SETUP
    const test_name = "Endpoint Exercise | Edit Entry";
    const ht = @import("httpz").testing;
    const Create = @import("../../models/exercise/exercise.zig").Create;
    const CreateCategory = @import("../../models/exercise/category.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const category_request = CreateCategory.Request{ .name = "Chest" };

    const category = try CreateCategory.call(user.id, test_env.database, category_request);

    var category_ids = [_]i32{category.id};
    const create_request = Create.Request{
        .name = test_name ++ " exercise",
        .base_amount = 1,
        .base_unit = test_name ++ "'s plates",
        .category_ids = &category_ids,
    };

    const exercise = try Create.call(user.id, test_env.database, create_request);

    const log_request = LogExercise.Request{
        .exercise_id = @intCast(exercise.id),
        .unit_id = @intCast(exercise.base_unit_id),
        .value = 123,
    };
    const log_response = try LogExercise.call(user.id, test_env.database, log_request);
    const body = EditExerciseEntry.Request{
        .value = 10,
        .notes = test_name ++ "'s notes",
    };
    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    const log_id = try std.fmt.allocPrint(allocator, "{}", .{log_response.id});
    defer allocator.free(log_id);

    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        web_test.param("entry_id", log_id);

        try editEntry(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(EditExerciseEntry.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expectEqual(user.id, response.value.created_by);
        try std.testing.expectEqual(exercise.base_unit_id, response.value.unit_id);
        try std.testing.expectEqual(exercise.id, response.value.exercise_id);
        try std.testing.expectEqual(body.value, response.value.value);
        if (response.value.notes) |notes| {
            try std.testing.expectEqualStrings(body.notes.?, notes);
        }
    }
}

test "Endpoint Exercise | Delete Entry" {
    // SETUP
    const test_name = "Endpoint Exercise | Delete Entry";
    const ht = @import("httpz").testing;
    const Create = @import("../../models/exercise/exercise.zig").Create;
    const CreateCategory = @import("../../models/exercise/category.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const category_request = CreateCategory.Request{ .name = "Chest" };

    const category = try CreateCategory.call(user.id, test_env.database, category_request);

    var category_ids = [_]i32{category.id};
    const create_request = Create.Request{
        .name = test_name ++ " exercise",
        .base_amount = 1,
        .base_unit = test_name ++ "'s plates",
        .category_ids = &category_ids,
    };

    const exercise = try Create.call(user.id, test_env.database, create_request);

    const log_request = LogExercise.Request{
        .exercise_id = @intCast(exercise.id),
        .unit_id = @intCast(exercise.base_unit_id),
        .value = 123,
    };

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    const log = try LogExercise.call(user.id, test_env.database, log_request);

    const log_id = try std.fmt.allocPrint(allocator, "{}", .{log.id});
    defer allocator.free(log_id);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("entry_id", log_id);

        try deleteEntry(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(LogExercise.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expectEqual(user.id, response.value.created_by);
        try std.testing.expectEqual(exercise.base_unit_id, response.value.unit_id);
        try std.testing.expectEqual(exercise.id, response.value.exercise_id);
        try std.testing.expectEqual(log_request.value, response.value.value);
    }
}

test "Endpoint Exercise | Get Range" {
    // SETUP
    const test_name = "Endpoint Exercise | Get Range";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    // create exercise category
    const CreateCategory = @import("../../models/exercise/category.zig").Create;
    const create_category_request = CreateCategory.Request{
        .name = test_name,
    };
    const create_category = try CreateCategory.call(user.id, test_env.database, create_category_request);

    // create exercise
    var create_exercise_web = ht.init(.{});
    defer create_exercise_web.deinit();

    const CreateExercise = @import("../../models/exercise/exercise.zig").Create;

    var category_ids = [_]i32{create_category.id};
    const create_exercise_request = CreateExercise.Request{
        .name = test_name,
        .base_amount = 123,
        .base_unit = test_name ++ "'s unit",
        .category_ids = &category_ids,
    };

    const create_exercise = try CreateExercise.call(user.id, test_env.database, create_exercise_request);

    // setup dates
    const zdt = @import("zdt");
    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .week));

    var lower_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.toString("%Y-%m-%d", &lower_bound_string.writer);
    try upper_bound.toString("%Y-%m-%d", &upper_bound_string.writer);

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    // log exercise
    const log_exercise = try LogExercise.call(user.id, test_env.database, .{
        .exercise_id = @intCast(create_exercise.id),
        .unit_id = @intCast(create_exercise.base_unit_id),
        .value = 123,
    });

    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.query("start", range_start);
        web_test.query("end", range_end);

        try getExerciseEntryRange(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]GetRange.EntryList, allocator, response_body, .{});
        defer response.deinit();

        for (response.value) |entry| {
            try std.testing.expectEqual(user.id, entry.created_by);
            try std.testing.expectEqual(log_exercise.id, entry.entry_id);
            try std.testing.expectEqual(create_category.id, entry.category_id);
            try std.testing.expectEqual(log_exercise.unit_id, entry.unit_id);
            try std.testing.expectEqualStrings(create_category.name, entry.category_name);
            try std.testing.expectEqual(log_exercise.value, entry.value);
        }
    }
}

const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");
const handleResponse = @import("../../response.zig").handleResponse;
const ResponseError = @import("../../response.zig").ResponseError;

const LogExercise = @import("../../models/exercise/exercise.zig").LogExercise;
const DeleteExerciseEntry = @import("../../models/exercise/exercise.zig").DeleteExerciseEntry;
const EditExerciseEntry = @import("../../models/exercise/exercise.zig").EditExerciseEntry;
const GetRange = @import("../../models/exercise/exercise.zig").GetRange;

const jsonStringify = @import("../../util/jsonStringify.zig").jsonStringify;

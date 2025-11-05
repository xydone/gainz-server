pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.get("/api/workout", getWorkout, .{ .data = &RouteData });
    router.*.get("/api/workout/:id/list", getWorkoutExerciseList, .{ .data = &RouteData });
    router.*.post("/api/workout", createWorkout, .{ .data = &RouteData });
    //TODO: currently this route allows anyone to modify any workout by adding exercises to it. This should be addressed in the future.
    router.*.post("/api/workout/:id/exercises", addExercises, .{ .data = &RouteData });
}

fn createWorkout(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try handleResponse(res, ResponseError.body_missing, null);
        return;
    };
    const workout = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try handleResponse(res, ResponseError.body_missing_fields, null);
        return;
    };
    const response = Create.call(ctx.user_id.?, ctx.app.db, workout) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(response, .{});
}
fn getWorkout(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const response = Get.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    defer ctx.app.allocator.free(response);

    res.status = 200;
    try res.json(response, .{});
}
fn getWorkoutExerciseList(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const id_param = req.param("id") orelse return error.NoIDParam;
    const workout_id = try std.fmt.parseInt(i32, id_param, 10);
    const response = GetExerciseList.call(ctx.app.allocator, workout_id, ctx.app.db) catch {
        try handleResponse(res, ResponseError.internal_server_error, null);
        return;
    };
    defer ctx.app.allocator.free(response);

    res.status = 200;
    try res.json(response, .{});
}

fn addExercises(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const id_param = req.param("id") orelse return error.NoIDParam;
    const workout_id = try std.fmt.parseInt(i32, id_param, 10);
    const body = req.body() orelse {
        try handleResponse(res, ResponseError.body_missing, null);
        return;
    };

    const workout = std.json.parseFromSliceLeaky([]AddExercise.Request, ctx.app.allocator, body, .{}) catch {
        try handleResponse(res, ResponseError.body_missing_fields, null);
        return;
    };
    defer ctx.app.allocator.free(workout);

    const response = AddExercise.call(ctx.app.allocator, workout_id, ctx.app.db, workout) catch |err| {
        switch (err) {
            AddExercise.Errors.InvalidExerciseID => {
                try handleResponse(res, ResponseError.not_found, "Invalid exercise ID!");
            },
            else => {
                try handleResponse(res, ResponseError.internal_server_error, null);
            },
        }
        return;
    };
    defer ctx.app.allocator.free(response);

    res.status = 200;
    try res.json(response, .{});
}

const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Endpoint Workout | Create" {
    // SETUP
    const test_name = "Endpoint Workout | Create";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const body = Create.Request{ .name = test_name };
    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        try createWorkout(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(Create.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expectEqual(user.id, response.value.created_by);
        try std.testing.expectEqualStrings(body.name, response.value.name);
    }
}

test "Endpoint Workout | Get" {
    // SETUP
    const test_name = "Endpoint Workout | Get";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const body = Create.Request{ .name = test_name };
    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    var create_web = ht.init(.{});
    defer create_web.deinit();

    create_web.body(body_string);

    try createWorkout(&context, create_web.req, create_web.res);
    const create_body = try create_web.getBody();
    const create_response = try std.json.parseFromSlice(Create.Response, allocator, create_body, .{});
    defer create_response.deinit();

    const inserted_responses = [_]Create.Response{create_response.value};

    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        try getWorkout(&context, web_test.req, web_test.res);

        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]Get.Response, allocator, response_body, .{});
        defer response.deinit();

        for (inserted_responses, response.value) |inserted, res| {
            try std.testing.expectEqual(inserted.id, res.id);
            try std.testing.expectEqual(inserted.created_at, res.created_at);
            try std.testing.expectEqual(inserted.created_by, res.created_by);
            try std.testing.expectEqualStrings(inserted.name, res.name);
        }
    }
}

test "Endpoint Workout | Add Exercises" {
    // SETUP
    const test_name = "Endpoint Workout | Add Exercises";
    const ht = @import("httpz").testing;
    const CreateExercise = @import("../models/exercise/exercise.zig").Create;
    const CreateCategory = @import("../models/exercise/category.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    // Create workout
    const workout = try Create.call(user.id, test_env.database, .{ .name = test_name });

    // Create exercise category
    const category = try CreateCategory.call(user.id, test_env.database, .{ .name = test_name ++ "'s category" });

    var category_ids = [_]i32{category.id};
    // Create exercise
    const exercise = try CreateExercise.call(user.id, test_env.database, .{
        .name = test_name ++ "'s exercise",
        .category_ids = &category_ids,
        .base_amount = 1,
        .base_unit = "kg",
    });

    const body = [_]AddExercise.Request{
        AddExercise.Request{
            .exercise_id = exercise.id,
            .notes = test_name ++ "'s notes!",
            .reps = 8,
            .sets = 3,
        },
    };

    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    const workout_id_string = try std.fmt.allocPrint(allocator, "{}", .{workout.id});
    defer allocator.free(workout_id_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("id", workout_id_string);
        web_test.body(body_string);

        try addExercises(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]AddExercise.Response, allocator, response_body, .{});
        defer response.deinit();

        for (body, response.value) |req, res| {
            try std.testing.expectEqual(req.exercise_id, res.exercise_id);

            try std.testing.expectEqual(workout.id, res.workout_id);

            try std.testing.expectEqual(req.reps, res.reps);

            try std.testing.expectEqual(req.sets, res.sets);

            try std.testing.expectEqualStrings(req.notes, res.notes);
        }
    }
}
test "Endpoint Workout | Add Exercise Invalid Exercise ID" {
    // SETUP
    const test_name = "Endpoint Workout | Add Exercise Invalid Exercise ID";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    // Create workout
    const workout = try Create.call(user.id, test_env.database, .{ .name = test_name });

    const nonexistent_exercise_id = std.math.maxInt(i32);
    const body = [_]AddExercise.Request{
        AddExercise.Request{
            .exercise_id = nonexistent_exercise_id,
            .notes = test_name ++ "'s notes!",
            .reps = 8,
            .sets = 3,
        },
    };

    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    const workout_id_string = try std.fmt.allocPrint(allocator, "{}", .{workout.id});
    defer allocator.free(workout_id_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("id", workout_id_string);
        web_test.body(body_string);

        try addExercises(&context, web_test.req, web_test.res);
        try web_test.expectStatus(404);
        const response_body = try web_test.getBody();

        const error_response = try std.json.parseFromSlice(ResponseError, allocator, response_body, .{});
        defer error_response.deinit();

        try std.testing.expectEqual(404, error_response.value.code);

        try std.testing.expectEqualStrings("Invalid exercise ID!", error_response.value.details.?);
    }
}

test "Endpoint Workout | Get Exercises List" {
    // SETUP
    const test_name = "Endpoint Workout | Get Exercises List";
    const ht = @import("httpz").testing;
    const CreateExercise = @import("../models/exercise/exercise.zig").Create;
    const CreateCategory = @import("../models/exercise/category.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    // Create workout
    const workout = try Create.call(user.id, test_env.database, .{ .name = test_name });

    // Create exercise category
    const category = try CreateCategory.call(user.id, test_env.database, .{ .name = test_name ++ "'s category" });

    var category_ids = [_]i32{category.id};

    // Create exercise
    const exercise = try CreateExercise.call(user.id, test_env.database, .{
        .name = test_name ++ "'s exercise",
        .category_ids = &category_ids,
        .base_amount = 1,
        .base_unit = "kg",
    });

    const body = [_]AddExercise.Request{
        AddExercise.Request{
            .exercise_id = exercise.id,
            .notes = test_name ++ "'s notes!",
            .reps = 8,
            .sets = 3,
        },
        AddExercise.Request{
            .exercise_id = exercise.id,
            .notes = test_name ++ "'s notes 2!",
            .reps = 13,
            .sets = 8,
        },
    };

    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    const workout_id_string = try std.fmt.allocPrint(allocator, "{}", .{workout.id});
    defer allocator.free(workout_id_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    var add_exercises = ht.init(.{});
    defer add_exercises.deinit();

    add_exercises.param("id", workout_id_string);
    add_exercises.body(body_string);

    try addExercises(&context, add_exercises.req, add_exercises.res);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("id", workout_id_string);
        web_test.body(body_string);

        try getWorkoutExerciseList(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]GetExerciseList.Response, allocator, response_body, .{});
        defer response.deinit();

        for (body, response.value) |req, res| {
            try std.testing.expectEqual(req.exercise_id, res.exercise_id);

            try std.testing.expectEqual(workout.id, res.workout_id);

            try std.testing.expectEqual(req.reps, res.reps);

            try std.testing.expectEqual(req.sets, res.sets);

            try std.testing.expectEqualStrings(req.notes, res.notes);
        }
    }
}

const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");
const handleResponse = @import("../response.zig").handleResponse;
const ResponseError = @import("../response.zig").ResponseError;

const Create = @import("../models/workout.zig").Create;
const Get = @import("../models/workout.zig").Get;
const GetExerciseList = @import("../models/workout.zig").GetExerciseList;
const AddExercise = @import("../models/workout.zig").AddExercise;

const jsonStringify = @import("../util/jsonStringify.zig").jsonStringify;

const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");
const rs = @import("../response.zig");
const Create = @import("../models/workout.zig").Create;
const Get = @import("../models/workout.zig").Get;
const AddExercise = @import("../models/workout.zig").AddExercise;

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };
    router.*.get("/api/workout", getWorkout, .{ .data = &RouteData });
    router.*.post("/api/workout", createWorkout, .{ .data = &RouteData });
    //TODO: currently this route allows anyone to modify any workout by adding exercises to it. This should be addressed in the future.
    router.*.post("/api/workout/:id/exercises", addExercises, .{ .data = &RouteData });
}

fn createWorkout(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const workout = std.json.parseFromSliceLeaky(Create.Request, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const response = Create.call(ctx.user_id.?, ctx.app.db, workout) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(response, .{});
}
fn getWorkout(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    _ = req; // autofix
    const response = Get.call(ctx.app.allocator, ctx.user_id.?, ctx.app.db) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
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
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };

    const workout = std.json.parseFromSliceLeaky([]AddExercise.Request, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    defer ctx.app.allocator.free(workout);

    const response = AddExercise.call(ctx.app.allocator, workout_id, ctx.app.db, workout) catch |err| {
        switch (err) {
            AddExercise.Errors.InvalidExerciseID => {
                try rs.handleResponse(res, rs.ResponseError.not_found, "Invalid exercise ID!");
            },
            else => {
                try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
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
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const body = Create.Request{ .name = test_name };
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

        createWorkout(&context, web_test.req, web_test.res) catch |err| {
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
        const response = std.json.parseFromSlice(Create.Response, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        std.testing.expectEqual(user.id, response.value.created_by) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(body.name, response.value.name) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "Endpoint Workout | Get" {
    // SETUP
    const test_name = "Endpoint Workout | Get";
    const ht = @import("httpz").testing;
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const body = Create.Request{ .name = test_name };
    const body_string = try std.json.stringifyAlloc(allocator, body, .{});
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
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        getWorkout(&context, web_test.req, web_test.res) catch |err| {
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
        const response = std.json.parseFromSlice([]Get.Response, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        for (inserted_responses, response.value) |inserted, res| {
            std.testing.expectEqual(inserted.id, res.id) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted.created_at, res.created_at) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted.created_by, res.created_by) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqualStrings(inserted.name, res.name) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

test "Endpoint Workout | Add Exercises" {
    // SETUP
    const test_name = "Endpoint Workout | Add Exercises";
    const ht = @import("httpz").testing;
    const Benchmark = @import("../tests/benchmark.zig");
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

    // Create exercise
    const exercise = try CreateExercise.call(user.id, test_env.database, .{
        .name = test_name ++ "'s exercise",
        .category_id = @intCast(category.id),
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

    const body_string = try std.json.stringifyAlloc(allocator, body, .{});
    defer allocator.free(body_string);

    const workout_id_string = try std.fmt.allocPrint(allocator, "{}", .{workout.id});
    defer allocator.free(workout_id_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("id", workout_id_string);
        web_test.body(body_string);

        addExercises(&context, web_test.req, web_test.res) catch |err| {
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
        const response = std.json.parseFromSlice([]AddExercise.Response, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        for (body, response.value) |req, res| {
            std.testing.expectEqual(req.exercise_id, res.exercise_id) catch |err| {
                benchmark.fail(err);
                return err;
            };

            std.testing.expectEqual(workout.id, res.workout_id) catch |err| {
                benchmark.fail(err);
                return err;
            };

            std.testing.expectEqual(req.reps, res.reps) catch |err| {
                benchmark.fail(err);
                return err;
            };

            std.testing.expectEqual(req.sets, res.sets) catch |err| {
                benchmark.fail(err);
                return err;
            };

            std.testing.expectEqualStrings(req.notes, res.notes) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}
test "Endpoint Workout | Add Exercise Invalid Exercise ID" {
    // SETUP
    const test_name = "Endpoint Workout | Add Exercise Invalid Exercise ID";
    const ht = @import("httpz").testing;
    const Benchmark = @import("../tests/benchmark.zig");
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

    const body_string = try std.json.stringifyAlloc(allocator, body, .{});
    defer allocator.free(body_string);

    const workout_id_string = try std.fmt.allocPrint(allocator, "{}", .{workout.id});
    defer allocator.free(workout_id_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("id", workout_id_string);
        web_test.body(body_string);

        addExercises(&context, web_test.req, web_test.res) catch |err| {
            benchmark.fail(err);
            return err;
        };
        web_test.expectStatus(404) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response_body = web_test.getBody() catch |err| {
            benchmark.fail(err);
            return err;
        };

        const error_response = std.json.parseFromSlice(rs.ResponseError, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer error_response.deinit();

        std.testing.expectEqual(404, error_response.value.code) catch |err| {
            benchmark.fail(err);
            return err;
        };

        std.testing.expectEqualStrings("Invalid exercise ID!", error_response.value.details.?) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

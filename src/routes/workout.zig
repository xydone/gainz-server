pub const endpoint_data = [_]EndpointData{
    Create.endpoint_data,
    GetAll.endpoint_data,
    GetExerciseList.endpoint_data,
    AddExercises.endpoint_data,
};

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Create.init(router);
    GetAll.init(router);
    GetExerciseList.init(router);
    // //TODO: currently this route allows anyone to modify any workout by adding exercises to it. This should be addressed in the future.
    AddExercises.init(router);
}
const Create = Endpoint(struct {
    const Body = CreateModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = CreateModel.Response,
        .path = "/api/workout",
        .method = .POST,
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const response = CreateModel.call(res.arena, ctx.user_id.?, ctx.app.db, request.body) catch {
            handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };

        res.status = 200;
        try res.json(response, .{});
    }
});

const GetAll = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{},
        .Response = GetModel.Response,
        .path = "/api/workout/",
        .method = .GET,
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, _: EndpointRequest(void, void, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const response = GetModel.call(allocator, ctx.user_id.?, ctx.app.db) catch {
            handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        defer allocator.free(response);

        res.status = 200;
        try res.json(response, .{});
    }
});

const GetExerciseList = Endpoint(struct {
    const Params = GetExerciseListModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = GetExerciseListModel.Response,
        .method = .GET,
        .path = "/api/workout/:workout_id/list",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const response = GetExerciseListModel.call(allocator, request.params, ctx.app.db) catch {
            handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        defer allocator.free(response);

        res.status = 200;
        try res.json(response, .{});
    }
});
const AddExercises = Endpoint(struct {
    const Body = []AddExerciseModel.Request;
    const Params = struct { workout_id: u32 };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
            .Params = Params,
        },
        .Response = AddExerciseModel.Response,
        .method = .POST,
        .path = "/api/workout/:workout_id/exercises",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;

        const response = AddExerciseModel.call(allocator, ctx.app.db, request.params.workout_id, request.body) catch |err| {
            switch (err) {
                AddExerciseModel.Errors.InvalidExerciseID => {
                    handleResponse(res, ResponseError.not_found, "Invalid exercise ID!");
                },
                else => {
                    handleResponse(res, ResponseError.internal_server_error, null);
                },
            }
            return;
        };
        defer allocator.free(response);

        res.status = 200;
        try res.json(response, .{});
    }
});
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

    const body = CreateModel.Request{ .name = test_name };
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

        try std.testing.expectEqual(user.id, response.value.created_by);
        try std.testing.expectEqualStrings(body.name, response.value.name);
    }
}

test "Endpoint Workout | GetAll" {
    // SETUP
    const test_name = "Endpoint Workout | GetAll";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const body = CreateModel.Request{ .name = test_name };
    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    var create_web = ht.init(.{});
    defer create_web.deinit();

    create_web.body(body_string);

    try Create.call(&context, create_web.req, create_web.res);
    const create_body = try create_web.getBody();
    const create_response = try std.json.parseFromSlice(CreateModel.Response, allocator, create_body, .{});
    defer create_response.deinit();

    const inserted_responses = [_]CreateModel.Response{create_response.value};

    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        try GetAll.call(&context, web_test.req, web_test.res);

        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]GetModel.Response, allocator, response_body, .{});
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
    const CreateUnit = @import("../models/exercise/unit.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    // Create workout
    const workout = try CreateModel.call(allocator, user.id, test_env.database, .{ .name = test_name });
    defer workout.deinit(allocator);

    const unit = try CreateUnit.call(allocator, user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });
    defer unit.deinit(allocator);

    var unit_ids = [_]i32{unit.id};
    // Create exercise category
    const category = try CreateCategory.call(allocator, user.id, test_env.database, .{ .name = test_name ++ "'s category" });
    defer category.deinit(allocator);

    var category_ids = [_]i32{category.id};
    // Create exercise
    const exercise = try CreateExercise.call(user.id, test_env.database, .{
        .name = test_name ++ "'s exercise",
        .category_ids = &category_ids,
        .unit_ids = &unit_ids,
    });

    const body = [_]AddExerciseModel.Request{
        AddExerciseModel.Request{
            .exercise_id = @intCast(exercise.id),
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

        web_test.param("workout_id", workout_id_string);
        web_test.body(body_string);

        try AddExercises.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]AddExerciseModel.Response, allocator, response_body, .{});
        defer response.deinit();

        for (body, response.value) |req, res| {
            try std.testing.expectEqual(req.exercise_id, @as(u32, @intCast(res.exercise_id)));

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
    const workout = try CreateModel.call(allocator, user.id, test_env.database, .{ .name = test_name });
    defer workout.deinit(allocator);

    const nonexistent_exercise_id = std.math.maxInt(i32);
    const body = [_]AddExerciseModel.Request{
        AddExerciseModel.Request{
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

        web_test.param("workout_id", workout_id_string);
        web_test.body(body_string);

        try AddExercises.call(&context, web_test.req, web_test.res);
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
    const CreateUnit = @import("../models/exercise/unit.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    // Create workout
    const workout = try CreateModel.call(allocator, user.id, test_env.database, .{ .name = test_name });
    defer workout.deinit(allocator);

    const unit = try CreateUnit.call(allocator, user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });
    defer unit.deinit(allocator);

    var unit_ids = [_]i32{unit.id};
    // Create exercise category
    const category = try CreateCategory.call(allocator, user.id, test_env.database, .{ .name = test_name ++ "'s category" });
    defer category.deinit(allocator);

    var category_ids = [_]i32{category.id};

    // Create exercise
    const exercise = try CreateExercise.call(user.id, test_env.database, .{
        .name = test_name ++ "'s exercise",
        .category_ids = &category_ids,
        .unit_ids = &unit_ids,
    });

    const body = [_]AddExerciseModel.Request{
        AddExerciseModel.Request{
            .exercise_id = @intCast(exercise.id),
            .notes = test_name ++ "'s notes!",
            .reps = 8,
            .sets = 3,
        },
        AddExerciseModel.Request{
            .exercise_id = @intCast(exercise.id),
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

    add_exercises.param("workout_id", workout_id_string);
    add_exercises.body(body_string);

    try AddExercises.call(&context, add_exercises.req, add_exercises.res);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("workout_id", workout_id_string);
        web_test.body(body_string);

        try GetExerciseList.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]GetExerciseListModel.Response, allocator, response_body, .{});
        defer response.deinit();

        for (body, response.value) |req, res| {
            try std.testing.expectEqual(req.exercise_id, @as(u32, @intCast(res.exercise_id)));

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

const CreateModel = @import("../models/workout.zig").Create;
const GetModel = @import("../models/workout.zig").Get;
const GetExerciseListModel = @import("../models/workout.zig").GetExerciseList;
const AddExerciseModel = @import("../models/workout.zig").AddExercise;

const jsonStringify = @import("../util/jsonStringify.zig").jsonStringify;

const Endpoint = @import("../endpoint.zig").Endpoint;
const EndpointRequest = @import("../endpoint.zig").EndpointRequest;
const EndpointData = @import("../endpoint.zig").EndpointData;

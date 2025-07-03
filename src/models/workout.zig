const std = @import("std");

const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;

const log = std.log.scoped(.workout_model);

pub const Create = struct {
    pub const Request = struct {
        name: []const u8,
    };
    pub const Response = struct {
        id: i32,
        name: []const u8,
        created_at: i64,
        created_by: i32,
    };
    pub const Errors = error{ CannotCreate, CannotParseResult } || DatabaseErrors;

    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const error_handler = ErrorHandler{ .conn = conn };

        var result = conn.row(query_string, .{ user_id, request.name }) catch |err| {
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer result.deinit() catch {};

        const response = result.to(Response, .{ .dupe = true }) catch return error.CannotParseResult;
        return response;
    }

    const query_string =
        \\INSERT INTO
        \\training.workout (created_by, name)
        \\VALUES
        \\($1, $2)
        \\RETURNING *;
    ;
};

pub const AddExercise = struct {
    pub const Request = struct {
        exercise_id: i32,
        notes: []const u8,
        sets: i32,
        reps: i32,
    };
    pub const Response = struct {
        workout_id: i32,
        exercise_id: i32,
        notes: []const u8,
        sets: i32,
        reps: i32,
    };
    pub const Errors = error{ CannotCreate, CannotParseResult, InvalidExerciseID } || DatabaseErrors;

    pub fn call(user_id: i32, workout_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const error_handler = ErrorHandler{ .conn = conn };

        var result = conn.row(query_string, .{
            workout_id,
            request.exercise_id,
            request.notes,
            request.sets,
            request.reps,
            user_id,
        }) catch |err| {
            const error_data = error_handler.handle(err) orelse return error.CannotCreate;
            if (std.mem.eql(u8, "23503", error_data.code)) {
                return error.InvalidExerciseID;
            }
            // unknown error code, returning default error information
            ErrorHandler.printErr(error_data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer result.deinit() catch {};

        const response = result.to(Response, .{ .dupe = true }) catch return error.CannotParseResult;
        return response;
    }

    const query_string =
        \\WITH authorized_workout AS (
        \\SELECT id
        \\FROM training.workout
        \\WHERE id = $1 AND created_by = $6
        \\),    
        \\inserted AS (
        \\INSERT INTO training.workout_exercise (workout_id, exercise_id, notes, sets, reps)
        \\SELECT $1, $2, $3, $4, $5
        \\FROM authorized_workout
        \\ON CONFLICT (workout_id, exercise_id) DO NOTHING
        \\RETURNING *
        \\)
        \\SELECT * FROM inserted;
    ;
};

const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "API Workout | Create" {
    const test_name = "API Workout | Create";
    //SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        const response = Create.call(
            setup.user.id,
            test_env.database,
            .{ .name = test_name },
        ) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(setup.user.id, response.created_by) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(test_name, response.name) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}
test "API Workout | Add Exercise" {
    const test_name = "API Workout | Add Exercise";
    //SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const CreateExercise = @import("exercise/exercise.zig").Create;
    const CreateCategory = @import("exercise/category.zig").Create;
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const workout = try Create.call(setup.user.id, test_env.database, .{ .name = test_name });
    const category = try CreateCategory.call(setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    const exercise = try CreateExercise.call(setup.user.id, test_env.database, .{
        .category_id = @intCast(category.id),
        .base_amount = 1,
        .base_unit = "kg",
        .name = "Bench press",
    });
    const request = AddExercise.Request{
        .exercise_id = @intCast(exercise.id),
        .notes = "Example notes",
        .sets = 6,
        .reps = 10,
    };

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        const response = AddExercise.call(setup.user.id, workout.id, test_env.database, request) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(request.exercise_id, response.exercise_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(workout.id, response.workout_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(request.reps, response.reps) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(request.sets, response.sets) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(request.notes, response.notes) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

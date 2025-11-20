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

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
        }
    };
    pub const Errors = error{ CannotCreate, CannotParseResult } || DatabaseErrors;

    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const error_handler = ErrorHandler{ .conn = conn };

        var result = conn.row(query_string, .{ user_id, request.name }) catch |err| {
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer result.deinit() catch {};

        const response = result.to(Response, .{ .allocator = allocator }) catch return error.CannotParseResult;
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

pub const Get = struct {
    pub const Request = struct {};
    pub const Response = struct {
        id: i32,
        name: []const u8,
        created_at: i64,
        created_by: i32,

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
        }
    };
    pub const Errors = error{
        CannotGet,
        CannotParseResult,
        OutOfMemory,
    } || DatabaseErrors;

    /// Caller must free slice
    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool) Errors![]Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const error_handler = ErrorHandler{ .conn = conn };

        var query = conn.query(query_string, .{user_id}) catch |err| {
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        };
        defer query.deinit();

        var response: std.ArrayList(Response) = .empty;

        while (query.next() catch return error.CannotGet) |result| {
            response.append(allocator, result.to(Response, .{ .allocator = allocator }) catch return error.CannotParseResult) catch return error.OutOfMemory;
        }
        return response.toOwnedSlice(allocator);
    }

    const query_string =
        \\SELECT * FROM training.workout WHERE created_by = $1
    ;
};

// NOTE: Reason for AddExercise not following the standard way of implementing the request structure.
// The reason behind the decision is due to the fact we accept a list of mulitple exercises for the same workout ID.
// This would either require data duplication or unneccesary expensive loop operations per call inside the HTTP client.
pub const AddExercise = struct {
    pub const Request = struct {
        exercise_id: u32,
        notes: []const u8,
        sets: i32,
        reps: i32,
    };
    pub const Response = struct {
        id: i32,
        workout_id: i32,
        exercise_id: i32,
        notes: []const u8,
        sets: i32,
        reps: i32,

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            allocator.free(self.notes);
        }
    };
    pub const Errors = error{
        CannotCreate,
        CannotParseResult,
        InvalidExerciseID,
        OutOfMemory,
    } || DatabaseErrors;

    /// Caller must free slice
    pub fn call(allocator: std.mem.Allocator, database: *Pool, workout_id: u32, request: []Request) Errors![]Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const error_handler = ErrorHandler{ .conn = conn };
        var query = Query.init(allocator, query_string_prefix, query_string_suffix);
        defer query.deinit();

        query.build(1, request.len * 5, 5) catch return error.CannotCreate;
        const joined = query.getJoined() catch return error.CannotCreate;
        defer allocator.free(joined);

        var stmt = conn.prepare(joined) catch return error.CannotCreate;
        errdefer stmt.deinit();

        for (request) |exercise| {
            stmt.bind(workout_id) catch return error.CannotCreate;
            stmt.bind(exercise.exercise_id) catch return error.CannotCreate;
            stmt.bind(exercise.notes) catch return error.CannotCreate;
            stmt.bind(exercise.sets) catch return error.CannotCreate;
            stmt.bind(exercise.reps) catch return error.CannotCreate;
        }

        var result = stmt.execute() catch |err| {
            const error_data = error_handler.handle(err) orelse return error.CannotCreate;
            if (std.mem.eql(u8, "23503", error_data.code)) {
                return error.InvalidExerciseID;
            }
            // unknown error code, returning default error information
            ErrorHandler.printErr(error_data);
            return error.CannotCreate;
        };
        defer result.deinit();

        var response: std.ArrayList(Response) = .empty;

        while (result.next() catch return error.CannotCreate) |row| {
            const res = row.to(Response, .{ .allocator = allocator }) catch return error.CannotCreate;
            response.append(allocator, res) catch return error.OutOfMemory;
        }

        return response.toOwnedSlice(allocator);
    }

    const query_string_prefix =
        \\INSERT INTO training.workout_exercise (workout_id, exercise_id, notes, sets, reps)
        \\VALUES 
    ;
    const query_string_suffix =
        \\RETURNING *
    ;
};

pub const GetExerciseList = struct {
    pub const Request = struct {
        workout_id: u32,
    };
    pub const Response = struct {
        workout_id: i32,
        workout_name: []const u8,
        exercise_id: i32,
        sets: i32,
        reps: i32,
        notes: []const u8,
        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            allocator.free(self.workout_name);
            allocator.free(self.notes);
        }
    };
    pub const Errors = error{
        CannotGet,
        CannotParseResult,
        OutOfMemory,
    } || DatabaseErrors;
    pub fn call(allocator: std.mem.Allocator, request: Request, database: *Pool) Errors![]Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const error_handler = ErrorHandler{ .conn = conn };

        var query = conn.query(query_string, .{request.workout_id}) catch |err| {
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        };
        defer query.deinit();

        var response: std.ArrayList(Response) = .empty;

        while (query.next() catch return error.CannotGet) |result| {
            response.append(allocator, result.to(Response, .{ .allocator = allocator }) catch return error.CannotParseResult) catch return error.OutOfMemory;
        }
        return response.toOwnedSlice(allocator);
    }

    const query_string =
        \\SELECT 
        \\w.id AS workout_id,
        \\w.name AS workout_name,
        \\we.exercise_id,
        \\we.sets,
        \\we.reps,
        \\we.notes
        \\FROM training.workout w
        \\JOIN training.workout_exercise we ON w.id = we.workout_id
        \\WHERE w.id = $1;
    ;
};

const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "API Workout | Create" {
    const test_name = "API Workout | Create";
    //SETUP
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    // TEST
    {
        const response = try Create.call(
            allocator,
            setup.user.id,
            test_env.database,
            .{ .name = test_name },
        );
        defer response.deinit(allocator);

        try std.testing.expectEqual(setup.user.id, response.created_by);
        try std.testing.expectEqualStrings(test_name, response.name);
    }
}

test "API Workout | Get" {
    const test_name = "API Workout | Get";
    //SETUP
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);
    const create = try Create.call(
        allocator,
        setup.user.id,
        test_env.database,
        .{ .name = test_name },
    );
    defer create.deinit(allocator);

    const create_responses = [_]Create.Response{create};
    // TEST
    {
        const response = try Get.call(allocator, setup.user.id, test_env.database);
        defer {
            for (response) |value| value.deinit(allocator);
            allocator.free(response);
        }
        for (create_responses, response) |created, res| {
            try std.testing.expectEqual(created.id, res.id);
            try std.testing.expectEqual(created.created_by, res.created_by);
            try std.testing.expectEqual(created.created_at, res.created_at);
            try std.testing.expectEqualStrings(created.name, res.name);
        }
    }
}

test "API Workout | Add Exercise" {
    const test_name = "API Workout | Add Exercise";
    //SETUP
    const CreateExercise = @import("exercise/exercise.zig").Create;
    const CreateCategory = @import("exercise/category.zig").Create;
    const CreateUnit = @import("exercise/unit.zig").Create;
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const workout = try Create.call(allocator, setup.user.id, test_env.database, .{ .name = test_name });
    defer workout.deinit(allocator);

    const category = try CreateCategory.call(allocator, setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    defer category.deinit(allocator);

    const unit = try CreateUnit.call(allocator, setup.user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });
    defer unit.deinit(allocator);

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    const exercise = try CreateExercise.call(setup.user.id, test_env.database, .{
        .category_ids = &category_ids,
        .unit_ids = &unit_ids,
        .name = "Bench press",
    });
    var request = [_]AddExercise.Request{
        AddExercise.Request{
            .exercise_id = @intCast(exercise.id),
            .notes = "Example notes",
            .sets = 6,
            .reps = 10,
        },
    };

    // TEST
    {
        const response = try AddExercise.call(allocator, test_env.database, @intCast(workout.id), &request);
        defer {
            for (response) |value| value.deinit(allocator);
            allocator.free(response);
        }
        for (request, response) |req, res| {
            try std.testing.expectEqual(req.exercise_id, @as(u32, @intCast(res.exercise_id)));
            try std.testing.expectEqual(workout.id, res.workout_id);
            try std.testing.expectEqual(req.reps, res.reps);
            try std.testing.expectEqual(req.sets, res.sets);
            try std.testing.expectEqualStrings(req.notes, res.notes);
        }
    }
}

test "API Workout | Get Exercise List" {
    const test_name = "API Workout | Get Exercise List";
    //SETUP
    const CreateExercise = @import("exercise/exercise.zig").Create;
    const CreateCategory = @import("exercise/category.zig").Create;
    const CreateUnit = @import("exercise/unit.zig").Create;
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const workout = try Create.call(allocator, setup.user.id, test_env.database, .{ .name = test_name });
    defer workout.deinit(allocator);

    const category = try CreateCategory.call(allocator, setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    defer category.deinit(allocator);

    const unit = try CreateUnit.call(allocator, setup.user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });
    defer unit.deinit(allocator);

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    const exercise = try CreateExercise.call(setup.user.id, test_env.database, .{
        .category_ids = &category_ids,
        .unit_ids = &unit_ids,
        .name = "Bench press",
    });
    var add_exercise_request = [_]AddExercise.Request{
        AddExercise.Request{
            .exercise_id = @intCast(exercise.id),
            .notes = "Example notes",
            .sets = 6,
            .reps = 10,
        },
        AddExercise.Request{
            .exercise_id = @intCast(exercise.id),
            .notes = "Example notes 2",
            .sets = 16,
            .reps = 15,
        },
    };

    const add_exercise_response = try AddExercise.call(allocator, test_env.database, @intCast(workout.id), &add_exercise_request);
    defer {
        for (add_exercise_response) |value| value.deinit(allocator);
        allocator.free(add_exercise_response);
    }
    // TEST
    {
        const request: GetExerciseList.Request = .{ .workout_id = @intCast(workout.id) };
        const response = try GetExerciseList.call(allocator, request, test_env.database);
        defer {
            for (response) |value| value.deinit(allocator);
            allocator.free(response);
        }
        for (add_exercise_request, response) |req, res| {
            try std.testing.expectEqual(req.exercise_id, @as(u32, @intCast(res.exercise_id)));
            try std.testing.expectEqual(workout.id, res.workout_id);
            try std.testing.expectEqual(req.reps, res.reps);
            try std.testing.expectEqual(req.sets, res.sets);
            try std.testing.expectEqualStrings(req.notes, res.notes);
        }
    }
}

const std = @import("std");

const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;
const Query = @import("../util/query_builder.zig").Query;

const std = @import("std");

const Pool = @import("../../db.zig").Pool;
const DatabaseErrors = @import("../../db.zig").DatabaseErrors;
const ErrorHandler = @import("../../db.zig").ErrorHandler;

const Handler = @import("../../handler.zig");
const rq = @import("../../request.zig");
const log = std.log.scoped(.exercise_model);

pub const Create = struct {
    pub const Request = struct {
        name: []const u8,
        description: ?[]const u8 = null,
        base_amount: f64,
        base_unit: []const u8,
        category_id: u32,
    };
    pub const Response = struct {
        id: i32,
        created_by: i32,
        name: []const u8,
        description: ?[]const u8,
        base_unit_id: i32,
    };
    pub const Errors = error{ CannotCreate, CannotParseResult } || DatabaseErrors;

    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var row = conn.row(query_string, //
            .{ user_id, request.name, request.description, request.base_amount, request.base_unit, request.category_id }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer row.deinit() catch {};

        return row.to(Response, .{}) catch return error.CannotParseResult;
    }
    const query_string =
        \\WITH
        \\inserted_exercise AS (
        \\INSERT INTO training.exercise (created_by, name, description)
        \\VALUES ($1, $2, $3)
        \\RETURNING id, created_by, name, description
        \\),
        \\inserted_unit AS (
        \\INSERT INTO training.exercise_unit (created_by, amount, unit, multiplier)
        \\SELECT $1, $4, $5, 1
        \\FROM inserted_exercise
        \\RETURNING id AS unit_id
        \\),
        \\inserted_category AS (
        \\INSERT INTO training.exercise_has_category (exercise_id, category_id)
        \\SELECT id, $6
        \\FROM inserted_exercise
        \\)
        \\SELECT e.*, u.unit_id
        \\FROM inserted_exercise e, inserted_unit u;
    ;
};

pub const GetAll = struct {
    pub const Request = struct {};
    pub const Response = struct {
        list: []Exercise,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Response) void {
            self.allocator.free(self.list);
        }
    };

    const Exercise = struct {
        id: i32,
        name: []const u8,
        description: ?[]const u8,
    };
    pub const Errors = error{
        CannotGet,
        CannotParseResult,
        OutOfMemory,
    } || DatabaseErrors;

    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var result = conn.queryOpts(query_string, .{user_id}, .{ .column_names = true }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        };
        defer result.deinit();
        var response = std.ArrayList(Exercise).init(allocator);
        while (result.next() catch return error.CannotGet) |row| {
            const id = row.get(i32, 0);

            const name = row.getCol([]u8, "name");
            const description = row.getCol(?[]u8, "description");

            response.append(Exercise{
                .id = id,
                .name = allocator.dupe(u8, name) catch return error.OutOfMemory,
                .description = if (description == null) null else allocator.dupe(u8, description.?) catch return error.OutOfMemory,
            }) catch return error.OutOfMemory;
        }
        return Response{ .list = response.toOwnedSlice() catch return error.OutOfMemory, .allocator = allocator };
    }
    const query_string = "SELECT id,name, description FROM training.exercise WHERE created_by = $1";
};

pub const LogExercise = struct {
    pub const Request = struct {
        exercise_id: u32,
        unit_id: u32,
        value: f32,
        notes: ?[]const u8 = null,
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        created_by: i32,
        exercise_id: i32,
        value: f64,
        unit_id: i32,
        notes: ?[]const u8,
    };
    pub const Errors = error{
        CannotLog,
        CannotParseResult,
    } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        const row = conn.row(query_string, .{ user_id, request.exercise_id, request.value, request.unit_id, request.notes }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotLog;
        } orelse return error.CannotLog;

        return row.to(Response, .{}) catch return error.CannotParseResult;
    }
    const query_string =
        \\INSERT INTO
        \\training.exercise_entry (created_by, exercise_id, value, unit_id, notes)
        \\VALUES
        \\($1, $2, $3, $4, $5)
        \\RETURNING *
    ;
};

const Tests = @import("../../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "API Exercise | Create" {
    const test_name = "API Exercise | Create";
    //SETUP
    const Benchmark = @import("../../tests/benchmark.zig");
    const CreateCategory = @import("category.zig").Create;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const category = try CreateCategory.call(setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        const request = Create.Request{
            .name = test_name,
            .category_id = @intCast(category.id),
            .base_amount = 1,
            .base_unit = "kg",
        };
        const response = Create.call(setup.user.id, test_env.database, request) catch |err| {
            benchmark.fail(err);
            return err;
        };

        std.testing.expectEqual(request.description, response.description) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(request.name, response.name) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "API Exercise | Log" {
    const test_name = "API Exercise | Log";
    //SETUP
    const Benchmark = @import("../../tests/benchmark.zig");
    const CreateCategory = @import("category.zig").Create;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const category = try CreateCategory.call(setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    const create_request = Create.Request{
        .name = test_name,
        .category_id = @intCast(category.id),
        .base_amount = 1,
        .base_unit = "kg",
    };
    const create_response = try Create.call(setup.user.id, test_env.database, create_request);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        const request = LogExercise.Request{
            .exercise_id = @intCast(create_response.id),
            .unit_id = @intCast(create_response.base_unit_id),
            .value = 15,
        };
        const response = LogExercise.call(setup.user.id, test_env.database, request) catch |err| {
            benchmark.fail(err);
            return err;
        };

        std.testing.expectEqual(@as(i32, @intCast(request.exercise_id)), response.exercise_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(@as(i32, @intCast(request.unit_id)), response.unit_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(request.value, response.value) catch |err| {
            benchmark.fail(err);
            return err;
        };
        if (request.notes) |notes| {
            std.testing.expectEqualStrings(notes, response.notes.?) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

const std = @import("std");

const Pool = @import("../../db.zig").Pool;
const DatabaseErrors = @import("../../db.zig").DatabaseErrors;
const ErrorHandler = @import("../../db.zig").ErrorHandler;

const Handler = @import("../../handler.zig");
const rq = @import("../../request.zig");
const log = std.log.scoped(.exercise_model);

pub const ExerciseList = struct {
    list: []Exercise,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ExerciseList) void {
        self.allocator.free(self.list);
    }
};

pub const Exercise = struct {
    id: i32,
    name: []const u8,
    description: ?[]const u8,
};

pub const Create = struct {
    pub const Request = struct {
        name: []const u8,
        description: ?[]const u8 = null,
        base_amount: f64,
        base_unit: []const u8,
        category_id: u32,
    };
    pub const Response = Exercise;
    pub const Errors = error{ CannotCreate, CannotParseResult } || DatabaseErrors;

    pub fn call(user_id: i32, database: *Pool, request: Request) anyerror!Response {
        var conn = try database.acquire();
        defer conn.release();

        var row = try conn.row(query_string, //
            .{ user_id, request.name, request.description, request.base_amount, request.base_unit, request.category_id }) orelse return error.CannotCreate;
        defer row.deinit() catch {};

        const id = row.get(i32, 0);
        const name = row.get([]u8, 2);
        const description = row.get(?[]u8, 3);
        return Exercise{ .id = id, .name = name, .description = description };
    }
    const query_string =
        \\WITH
        \\inserted_exercise AS (
        \\INSERT INTO training.exercise (created_by, name, description)
        \\VALUES ($1, $2, $3)
        \\RETURNING id, created_by, name,description
        \\),
        \\inserted_unit AS (
        \\INSERT INTO training.exercise_unit (created_by, amount, unit, multiplier)
        \\SELECT $1, $4, $5, 1
        \\FROM inserted_exercise
        \\),
        \\inserted_category AS (
        \\INSERT INTO training.exercise_has_category (exercise_id, category_id)
        \\SELECT id, $6
        \\FROM inserted_exercise
        \\)
        \\SELECT * FROM inserted_exercise;
    ;
};

pub const GetAll = struct {
    pub const Request = struct {};
    pub const Response = ExerciseList;
    pub const Errors = error{ CannotGet, CannotParseResult } || DatabaseErrors;

    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool) anyerror!Response {
        var conn = try database.acquire();
        defer conn.release();

        var result = conn.queryOpts(query_string, .{user_id}, .{ .column_names = true }) catch |err| {
            if (conn.err) |pg_err| {
                log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
            }
            return err;
        };
        defer result.deinit();
        var response = std.ArrayList(Exercise).init(allocator);
        while (try result.next()) |row| {
            const id = row.get(i32, 0);

            const name = row.getCol([]u8, "name");
            const description = row.getCol(?[]u8, "description");

            try response.append(Exercise{
                .id = id,
                .name = try allocator.dupe(u8, name),
                .description = if (description == null) null else try allocator.dupe(u8, description.?),
            });
        }
        return ExerciseList{ .list = try response.toOwnedSlice(), .allocator = allocator };
    }
    const query_string = "SELECT id,name, description FROM training.exercise WHERE created_by = $1";
};

pub const LogExercise = struct {
    pub const Request = struct {
        exercise_id: u32,
        unit_id: u32,
        value: f32,
        notes: ?[]u8 = null,
    };
    pub fn call(ctx: *Handler.RequestContext, request: Request) anyerror!void {
        var conn = try ctx.app.db.acquire();
        defer conn.release();

        _ = try conn.exec(query_string, .{ ctx.user_id, request.exercise_id, request.value, request.unit_id, request.notes });
    }
    const query_string =
        \\INSERT INTO
        \\exercise_entry (created_by, exercise_id, value, unit_id, notes)
        \\VALUES
        \\($1, $2, $3, $4, $5)
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

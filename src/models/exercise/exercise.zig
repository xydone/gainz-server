const std = @import("std");

const pg = @import("pg");

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
    id: i64,
    name: []const u8,
    description: ?[]const u8,
};

pub fn getAll(allocator: std.mem.Allocator, user_id: i32, database: *pg.Pool) anyerror!ExerciseList {
    var conn = try database.acquire();
    defer conn.release();

    var result = conn.queryOpts(SQL_STRINGS.getExercises, .{user_id}, .{ .column_names = true }) catch |err| {
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

pub fn create(ctx: *Handler.RequestContext, request: rq.PostExercise) anyerror!Exercise {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var row = try conn.row(SQL_STRINGS.createExercise, //
        .{ ctx.user_id, request.name, request.description, request.base_amount, request.base_unit, request.category_id }) orelse return error.ExerciseNotCreated;
    defer row.deinit() catch {};

    const id = row.get(i32, 0);
    const name = row.get([]u8, 2);
    const description = row.get(?[]u8, 3);
    return Exercise{ .id = id, .name = name, .description = description };
}

pub fn logExercise(ctx: *Handler.RequestContext, request: rq.PostExerciseEntry) anyerror!void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    _ = try conn.exec(SQL_STRINGS.createExerciseEntry, .{ ctx.user_id, request.exercise_id, request.value, request.unit_id, request.notes });
}

const SQL_STRINGS = struct {
    pub const createExercise =
        \\WITH
        \\inserted_exercise AS (
        \\INSERT INTO exercise (created_by, name, description)
        \\VALUES ($1, $2, $3)
        \\RETURNING id, created_by, name,description
        \\),
        \\inserted_unit AS (
        \\INSERT INTO exercise_unit (created_by, amount, unit, multiplier)
        \\SELECT $1, $4, $5, 1
        \\FROM inserted_exercise
        \\),
        \\inserted_category AS (
        \\INSERT INTO exercise_has_category (exercise_id, category_id)
        \\SELECT id, $6
        \\FROM inserted_exercise
        \\)
        \\SELECT * FROM inserted_exercise;
    ;
    pub const createExerciseEntry =
        \\INSERT INTO
        \\exercise_entry (created_by, exercise_id, value, unit_id, notes)
        \\VALUES
        \\($1, $2, $3, $4, $5)
    ;
    pub const getExercises = "SELECT id,name, description FROM exercise WHERE created_by = $1";
};

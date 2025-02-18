const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");
const log = std.log.scoped(.exercise_model);

pub fn getExercises(ctx: *Handler.RequestContext) anyerror![]rs.GetExercises {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var result = conn.queryOpts(SQL_STRINGS.getExercises, .{ctx.user_id}, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(rs.GetExercises).init(ctx.app.allocator);
    while (try result.next()) |row| {
        const id = row.get(i32, 0);

        const name = row.getCol([]u8, "name");
        const description = row.getCol(?[]u8, "description");

        try response.append(rs.GetExercises{
            .id = id,
            .name = try ctx.app.allocator.dupe(u8, name),
            .description = if (description == null) null else try ctx.app.allocator.dupe(u8, description.?),
        });
    }
    return try response.toOwnedSlice();
}

pub fn createExercise(ctx: *Handler.RequestContext, request: rq.PostExercise) anyerror!void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    _ = try conn.exec(SQL_STRINGS.createExercise, .{ ctx.user_id, request.name, request.description, request.base_amount, request.base_unit, request.category_id });
}

pub fn createCategory(ctx: *Handler.RequestContext, request: rq.PostCategory) anyerror!void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    _ = try conn.exec(SQL_STRINGS.createCategory, .{ ctx.user_id, request.name, request.description });
}

pub fn createUnit(ctx: *Handler.RequestContext, request: rq.PostUnit) anyerror!void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    _ = try conn.exec(SQL_STRINGS.createUnit, .{ ctx.user_id, request.amount, request.unit, request.multiplier, request.exercise_id });
}

pub fn createExerciseEntry(ctx: *Handler.RequestContext, request: rq.PostExerciseEntry) anyerror!void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    _ = try conn.exec(SQL_STRINGS.createExerciseEntry, .{ ctx.user_id, request.exercise_id, request.value, request.unit_id, request.notes });
}

pub fn getCategories(ctx: *Handler.RequestContext) anyerror![]rs.GetCategories {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var result = conn.queryOpts(SQL_STRINGS.getCategories, .{ctx.user_id}, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(rs.GetCategories).init(ctx.app.allocator);
    while (try result.next()) |row| {
        const id = row.get(i32, 0);

        const name = row.getCol([]u8, "name");
        const description = row.getCol(?[]u8, "description");

        try response.append(rs.GetCategories{
            .id = id,
            .name = try ctx.app.allocator.dupe(u8, name),
            .description = if (description == null) null else try ctx.app.allocator.dupe(u8, description.?),
        });
    }
    return try response.toOwnedSlice();
}

const SQL_STRINGS = struct {
    pub const createExercise =
        \\WITH
        \\inserted_exercise AS (
        \\INSERT INTO
        \\exercise (created_by, name, description)
        \\VALUES
        \\($1, $2, $3)
        \\RETURNING
        \\id
        \\), inserted_unit AS (
        \\INSERT INTO
        \\exercise_unit (created_by, exercise_id, amount, unit, multiplier)
        \\SELECT
        \\$1,
        \\id,
        \\$4,
        \\$5,
        \\1
        \\FROM
        \\inserted_exercise
        \\)
        \\INSERT INTO
        \\exercise_has_category (exercise_id, category_id)
        \\SELECT
        \\id,
        \\$6
        \\FROM
        \\inserted_exercise;
    ;
    pub const createCategory =
        \\INSERT INTO
        \\exercise_category (created_by, name, description)
        \\VALUES
        \\($1, $2, $3)
    ;
    pub const createUnit =
        \\INSERT INTO
        \\exercise_unit (created_by, amount, unit, multiplier, exercise_id)
        \\VALUES
        \\($1, $2, $3, $4, $5)
    ;
    pub const createExerciseEntry =
        \\INSERT INTO
        \\exercise_entry (created_by, exercise_id, value, unit_id, notes)
        \\VALUES
        \\($1, $2, $3, $4, $5)
    ;
    pub const getCategories = "SELECT id,name, description FROM exercise_category WHERE created_by = $1";
    pub const getExercises = "SELECT id,name, description FROM exercise WHERE created_by = $1";
};

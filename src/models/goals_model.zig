const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.goals_model);

pub const Goals = struct {
    target: types.GoalTargets,
    value: f64,
    pub fn create(user_id: i32, database: *pg.Pool, request: rq.PostGoal) anyerror!Goals {
        var conn = try database.acquire();
        defer conn.release();
        var row = conn.row(SQL_STRINGS.create, //
            .{ user_id, request.target, request.value }) catch |err| {
            if (conn.err) |pg_err| {
                log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
            }
            return err;
        } orelse return error.GoalNotCreated;
        defer row.deinit() catch {};
        const target = row.get(types.GoalTargets, 0);
        const value = row.get(f64, 1);
        return Goals{ .target = target, .value = value };
    }

    pub fn get(allocator: std.mem.Allocator, user_id: i32, database: *pg.Pool) anyerror!rs.GetGoals {
        var conn = try database.acquire();
        defer conn.release();
        var row = conn.row(SQL_STRINGS.get, //
            .{user_id}) catch |err| {
            if (conn.err) |pg_err| {
                log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
            }
            return err;
        } orelse return error.NotFound;
        defer row.deinit() catch {};
        const goals = row.get(?[]u8, 0) orelse return error.NoGoals;
        const parsed = try std.json.parseFromSlice(rs.GetGoals, allocator, goals, .{});
        return parsed.value;
    }
};
const SQL_STRINGS = struct {
    pub const create = "insert into goals (created_by, target, value) values ($1,$2,$3) returning target, value";
    pub const get =
        \\ SELECT jsonb_object_agg(target, value) AS goals
        \\ FROM (
        \\ SELECT DISTINCT ON (target) target, value
        \\ FROM goals
        \\ WHERE created_by = $1
        \\ ORDER BY target, id DESC
        \\ ) sub;
    ;
};

//TESTS

const Tests = @import("../tests/tests.zig");

test "create goal" {
    const test_env = Tests.test_env;
    const create_goal = rq.PostGoal{ .target = .weight, .value = 85.13 };
    const goal = try Goals.create(1, test_env.database, create_goal);
    try std.testing.expectEqual(create_goal.target, goal.target);
    try std.testing.expectEqual(create_goal.value, goal.value);
}

test "get goal" {
    const test_env = Tests.test_env;
    const goals = try Goals.get(test_env.allocator, 1, test_env.database);
    const expected_goals = rs.GetGoals{ .weight = 85.13 };
    try std.testing.expectEqual(expected_goals, goals);
}

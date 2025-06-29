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

    pub fn get(allocator: std.mem.Allocator, user_id: i32, database: *pg.Pool) !std.json.Parsed(rs.GetGoals) {
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
        return parsed;
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
const TestSetup = Tests.TestSetup;

test "Goal | Create" {
    // SETUP
    const test_env = Tests.test_env;
    const Benchmark = @import("../tests/benchmark.zig");
    const test_name = "Goal | Create";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    const create_goal = rq.PostGoal{
        .target = .weight,
        .value = 85.13,
    };
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const goal = Goals.create(setup.user.id, test_env.database, create_goal) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_goal.target, goal.target) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_goal.value, goal.value) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "Goal | Get" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    const test_name = "Goal | Get";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    const create_goal = rq.PostGoal{
        .target = .weight,
        .value = 85.13,
    };
    const goal = try Goals.create(setup.user.id, test_env.database, create_goal);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const result = Goals.get(allocator, setup.user.id, test_env.database) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer result.deinit();

        std.testing.expectEqual(goal.value, result.value.weight) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

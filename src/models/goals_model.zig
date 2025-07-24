const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;

const log = std.log.scoped(.goals_model);

pub const Create = struct {
    pub const Request = struct {
        target: types.GoalTargets,
        value: f64,
    };
    pub const Response = struct {
        target: types.GoalTargets,
        value: f64,
    };
    pub const Errors = error{
        CannotCreate,
        CannotParseResult,
        OutOfMemory,
    } || DatabaseErrors;
    pub fn call(user_id: i32, database: *pg.Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var row = conn.row(query_string, //
            .{ user_id, request.target, request.value }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer row.deinit() catch {};

        return row.to(Response, .{}) catch return error.CannotParseResult;
    }

    const query_string = "INSERT INTO goals (created_by, target, value) VALUES ($1,$2,$3) RETURNING target, value";
};

pub const Get = struct {
    pub const Response = struct {
        weight: ?f64 = null,
        calories: ?f64 = null,
        //the reason why we set the following ones to default as null is because std.json.parseFromSliceLeaky(...) will just be unable to parse fields with either missing, which are not defaulted
        fat: ?f64 = null,
        sat_fat: ?f64 = null,
        polyunsat_fat: ?f64 = null,
        monounsat_fat: ?f64 = null,
        trans_fat: ?f64 = null,
        cholesterol: ?f64 = null,
        sodium: ?f64 = null,
        potassium: ?f64 = null,
        carbs: ?f64 = null,
        fiber: ?f64 = null,
        sugar: ?f64 = null,
        protein: ?f64 = null,
        vitamin_a: ?f64 = null,
        vitamin_c: ?f64 = null,
        calcium: ?f64 = null,
        iron: ?f64 = null,
        added_sugars: ?f64 = null,
        vitamin_d: ?f64 = null,
        sugar_alcohols: ?f64 = null,
    };
    pub const Errors = error{
        CannotGet,
        NoGoals,
        CannotParseResult,
        OutOfMemory,
    } || DatabaseErrors;

    /// Caller must free
    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *pg.Pool) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var row = conn.row(query_string, //
            .{user_id}) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        } orelse return error.CannotGet;
        defer row.deinit() catch {};
        const goals = row.get(?[]u8, 0) orelse return error.NoGoals;
        return std.json.parseFromSliceLeaky(Response, allocator, goals, .{}) catch return error.CannotParseResult;
    }

    const query_string =
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

test "API Goal | Create" {
    // SETUP
    const test_env = Tests.test_env;
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const test_name = "API Goal | Create";
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const create_goal = Create.Request{
        .target = .weight,
        .value = 85.13,
    };
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const goal = Create.call(setup.user.id, test_env.database, create_goal) catch |err| {
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

test "API Goal | Get" {
    // SETUP
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    const test_name = "API Goal | Get";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const create_goal = Create.Request{
        .target = .weight,
        .value = 85.13,
    };
    const goal = try Create.call(setup.user.id, test_env.database, create_goal);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const result = Get.call(allocator, setup.user.id, test_env.database) catch |err| {
            benchmark.fail(err);
            return err;
        };

        std.testing.expectEqual(goal.value, result.weight) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

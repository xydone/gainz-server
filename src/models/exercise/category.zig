const std = @import("std");

const Pool = @import("../../db.zig").Pool;
const DatabaseErrors = @import("../../db.zig").DatabaseErrors;
const ErrorHandler = @import("../../db.zig").ErrorHandler;

const Handler = @import("../../handler.zig");
const rq = @import("../../request.zig");
const rs = @import("../../response.zig");

const log = std.log.scoped(.category_model);

pub const Create = struct {
    pub const Request = struct {
        name: []const u8,
        description: ?[]const u8 = null,
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        created_by: i32,
        name: []const u8,
        description: ?[]const u8 = null,
    };
    pub const Errors = error{ CannotCreate, CannotParseResult } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var row = conn.row(query_string, .{ user_id, request.name, request.description }) catch {
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer row.deinit() catch {};

        const response = row.to(Response, .{ .dupe = true }) catch return error.CannotParseResult;
        return response;
    }
    const query_string =
        \\INSERT INTO
        \\training.exercise_category (created_by, name, description)
        \\VALUES
        \\($1, $2, $3)
        \\RETURNING *;
    ;
};

pub const Get = struct {
    pub const Request = struct {
        name: []u8,
        description: ?[]u8 = null,
    };
    pub const Response = struct {
        id: i32,
        name: []u8,
        description: ?[]u8 = null,
    };
    pub const Errors = error{ CannotGet, CannotParseResult } || DatabaseErrors;
    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool) anyerror![]rs.GetCategories {
        var conn = try database.acquire();
        defer conn.release();

        var result = conn.queryOpts(query_string, .{user_id}, .{ .column_names = true }) catch |err| {
            if (conn.err) |pg_err| {
                log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
            }
            return err;
        };
        defer result.deinit();
        var response = std.ArrayList(rs.GetCategories).init(allocator);
        while (try result.next()) |row| {
            const id = row.get(i32, 0);

            const name = row.getCol([]u8, "name");
            const description = row.getCol(?[]u8, "description");

            try response.append(rs.GetCategories{
                .id = id,
                .name = try allocator.dupe(u8, name),
                .description = if (description == null) null else try allocator.dupe(u8, description.?),
            });
        }
        return try response.toOwnedSlice();
    }
    const query_string = "SELECT id,name, description FROM training.exercise_category WHERE created_by = $1";
};

const Tests = @import("../../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "API Exercise Category | Create" {
    const test_name = "API Exercise Category | Create";
    //SETUP
    const Benchmark = @import("../../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        const request = Create.Request{ .name = "Chest" };
        const response = try Create.call(setup.user.id, test_env.database, .{
            .name = "Chest",
        });
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

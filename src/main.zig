const allocator = std.heap.smp_allocator;
const log = std.log.scoped(.main);
const PORT = 3000;
pub fn main() !void {
    const path = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(path);

    var env = try Env.init(allocator);
    defer env.deinit(allocator);

    const database = try db.init(allocator, env);
    defer database.deinit();

    var redis_client = try redis.RedisClient.init(allocator, env.ADDRESS, env.REDIS_PORT.?);
    defer redis_client.deinit();

    var handler = Handler{ .allocator = allocator, .db = database, .env = env, .redis_client = &redis_client };
    var server = try httpz.Server(*Handler).init(allocator, .{
        .port = PORT,
        .address = env.ADDRESS,
    }, &handler);
    defer server.deinit();
    defer server.stop();

    const cors = try server.middleware(Cors, .{
        .origin = "*",
        //NOTE: review what headers I'm actually allowing
        .headers = "*",
        .methods = "*",
    });
    const router = try server.router(.{ .middlewares = &.{cors} });

    // /api endpoints
    API.init(router);

    log.info("listening http://{s}:{d}/", .{ env.ADDRESS, PORT });

    try server.listen();
}

const Tests = @import("tests/tests.zig");

test "tests:beforeAll" {
    //Guarantee that this is only ran in a test environment
    try Tests.TestEnvironment.init();

    std.testing.refAllDecls(@This());
    _ = @import("endpoint.zig");
}

test "tests:afterAll" {
    var test_env = Tests.test_env;

    defer test_env.deinit();
}

const std = @import("std");

const httpz = @import("httpz");
const pg = @import("pg");

const db = @import("db.zig");
const Handler = @import("handler.zig");

const API = @import("routes/api.zig");
const Cors = @import("middleware/cors.zig");

const Env = @import("env.zig");
const redis = @import("util/redis.zig");
const types = @import("types.zig");

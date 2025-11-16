const allocator = std.heap.smp_allocator;
const log = std.log.scoped(.main);
const PORT = 3000;
pub fn main() !void {
    var env = try dotenv.init(allocator, ".env");
    defer env.deinit();

    _ = env.get("JWT_SECRET") orelse {
        log.err("The .env file is missing a \"JWT_SECRET\" parameter, please add it and try again!", .{});
        return;
    };
    const database = try db.init(allocator, env);
    defer database.deinit();

    const redis_port = try std.fmt.parseInt(u16, env.get("REDIS_PORT") orelse "6379", 10);

    var redis_client = try redis.RedisClient.init(allocator, "127.0.0.1", redis_port);
    defer redis_client.deinit();

    const address = env.get("ADDRESS") orelse "127.0.0.1";
    var handler = Handler{ .allocator = allocator, .db = database, .env = env, .redis_client = &redis_client };
    var server = try httpz.Server(*Handler).init(allocator, .{ .port = PORT, .address = address }, &handler);
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

    log.info("listening http://{s}:{d}/", .{ address, PORT });

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

const dotenv = @import("util/dotenv.zig").dotenv;
const redis = @import("util/redis.zig");
const types = @import("types.zig");

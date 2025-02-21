const std = @import("std");

const httpz = @import("httpz");
const pg = @import("pg");

const db = @import("db.zig");
const Handler = @import("handler.zig");

const API = @import("routes/api.zig");
const Cors = @import("middleware/cors.zig");

// UTIL
const dotenv = @import("util/dotenv.zig");
const redis = @import("util/redis.zig");
const types = @import("types.zig");

// var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
// const allocator = arena.allocator();
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

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

    var redis_client = try redis.RedisClient.init(allocator, "127.0.0.1", 6379);
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
    });
    const router = server.router(.{ .middlewares = &.{cors} });

    // /api endpoinds
    API.init(router);

    log.info("listening http://{s}:{d}/", .{ address, PORT });

    try server.listen();
}

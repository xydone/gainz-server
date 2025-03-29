const std = @import("std");
const pg = @import("pg");
const dotenv = @import("../util/dotenv.zig").dotenv;
const db = @import("../db.zig");
const redis = @import("../util/redis.zig");

pub var test_env: TestEnvironment = undefined;

pub const TestEnvironment = struct {
    allocator: std.mem.Allocator,
    database: *pg.Pool,
    env: dotenv,
    redis_client: redis.RedisClient,

    pub fn init() !void {
        const alloc = std.heap.smp_allocator;
        const env = try dotenv.init(alloc, ".testing.env");

        const database = try db.init(alloc, env);

        const redis_port = try std.fmt.parseInt(u16, env.get("REDIS_PORT").?, 10);
        const redis_client = try redis.RedisClient.init(alloc, "127.0.0.1", redis_port);

        test_env = TestEnvironment{ .allocator = alloc, .database = database, .env = env, .redis_client = redis_client };
    }
    pub fn deinit(self: *TestEnvironment) void {
        self.database.deinit();
        self.env.deinit();
        self.redis_client.deinit();
    }
};

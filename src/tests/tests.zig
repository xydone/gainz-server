const std = @import("std");
const pg = @import("pg");
const dotenv = @import("../util/dotenv.zig").dotenv;
const db = @import("../db.zig");
const redis = @import("../util/redis.zig");
const rq = @import("../request.zig");

pub var test_env: TestEnvironment = undefined;

pub const TestEnvironment = struct {
    database: *pg.Pool,
    env: dotenv,
    redis_client: redis.RedisClient,

    pub fn init() !void {
        const alloc = std.heap.smp_allocator;
        const env = try dotenv.init(alloc, ".testing.env");

        const database = try db.init(alloc, env);

        const redis_port = try std.fmt.parseInt(u16, env.get("REDIS_PORT").?, 10);
        const redis_client = try redis.RedisClient.init(alloc, "127.0.0.1", redis_port);

        test_env = TestEnvironment{ .database = database, .env = env, .redis_client = redis_client };
    }
    pub fn deinit(self: *TestEnvironment) void {
        self.database.deinit();
        self.env.deinit();
        self.redis_client.deinit();
    }
};

pub const TestSetup = struct {
    user: User,

    const User = @import("../models/users_model.zig").User;
    pub fn init(database: *pg.Pool, unique_name: []const u8) !TestSetup {
        const user = try createUser(database, unique_name);

        return TestSetup{
            .user = user,
        };
    }

    pub fn createUser(database: *pg.Pool, name: []const u8) !User {
        const allocator = std.testing.allocator;
        const innerCreate = @import("../models/users_model.zig").create;

        const username = try std.fmt.allocPrint(allocator, "{s}", .{name});
        defer allocator.free(username);
        const display_name = try std.fmt.allocPrint(allocator, "Display {s}", .{name});
        defer allocator.free(display_name);
        const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
        defer allocator.free(password);

        const request = rq.PostUser{
            .display_name = display_name,
            .username = username,
            .password = password,
        };
        const user = try innerCreate(
            database,
            allocator,
            request,
        );
        return user;
    }
    pub fn deinit(self: *TestSetup) void {
        self.user.deinit();
    }
};

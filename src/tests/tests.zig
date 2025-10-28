pub var test_env: TestEnvironment = undefined;

pub const TestEnvironment = struct {
    database: *pg.Pool,
    env: dotenv,
    redis_client: redis.RedisClient,

    const InitErrors = error{ CouldntInitializeDotenv, CouldntInitializeRedis, CouldntInitializeDB, NotRunningOnTestDB } || anyerror;

    /// Initializes the struct and clears all data from the database *only if* it is the test database
    pub fn init() InitErrors!void {
        const alloc = std.heap.smp_allocator;
        const env = dotenv.init(alloc, ".testing.env") catch return InitErrors.CouldntInitializeDotenv;

        const database = Database.init(alloc, env) catch return InitErrors.CouldntInitializeDB;

        const redis_port = std.fmt.parseInt(u16, env.get("REDIS_PORT") orelse return InitErrors.CouldntInitializeRedis, 10) catch return InitErrors.CouldntInitializeRedis;
        const redis_client = redis.RedisClient.init(alloc, "127.0.0.1", redis_port) catch return InitErrors.CouldntInitializeRedis;

        test_env = TestEnvironment{ .database = database, .env = env, .redis_client = redis_client };

        const conn = try database.acquire();
        defer conn.release();

        var row = try conn.row("SELECT current_database();", .{});
        const name = row.?.get([]u8, 0);
        try row.?.deinit();

        if (!std.mem.startsWith(u8, name, "TEST_")) return InitErrors.NotRunningOnTestDB;

        // Clear database
        var clean_db = try conn.row(
            \\SELECT 'TRUNCATE TABLE ' ||
            \\string_agg(quote_ident(table_name), ', ') ||
            \\' RESTART IDENTITY CASCADE;' AS sql_to_run
            \\FROM information_schema.tables
            \\WHERE table_schema = 'public' 
            \\AND table_type = 'BASE TABLE';
        , .{});
        const string = row.?.get([]u8, 0);
        try clean_db.?.deinit();

        _ = try conn.exec(string, .{});
    }
    pub fn deinit(self: *TestEnvironment) void {
        self.database.deinit();
        self.env.deinit();
        self.redis_client.deinit();
    }
};

pub const TestSetup = struct {
    user: User,

    const User = @import("../models/users_model.zig").Create.Response;
    pub fn init(database: *pg.Pool, unique_name: []const u8) !TestSetup {
        const user = try createUser(database, unique_name);

        return TestSetup{
            .user = user,
        };
    }

    pub fn createUser(database: *pg.Pool, name: []const u8) !User {
        const allocator = std.testing.allocator;
        const Create = @import("../models/users_model.zig").Create;

        const username = try std.fmt.allocPrint(allocator, "{s}", .{name});
        defer allocator.free(username);
        const display_name = try std.fmt.allocPrint(allocator, "Display {s}", .{name});
        defer allocator.free(display_name);
        const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
        defer allocator.free(password);

        const request = Create.Request{
            .display_name = display_name,
            .username = username,
            .password = password,
        };
        const user = try Create.call(
            database,
            allocator,
            request,
        );
        return user;
    }
    pub fn createContext(user_id: ?i32, allocator: std.mem.Allocator, database: *Database.Pool) !Handler.RequestContext {
        const app = try allocator.create(Handler);
        app.* = Handler{
            .allocator = allocator,
            .env = try dotenv.init(allocator, ".env"),
            .redis_client = &test_env.redis_client,
            .db = database,
        };
        return Handler.RequestContext{
            .app = app,
            .refresh_token = null,
            .user_id = user_id,
        };
    }
    pub fn deinitContext(allocator: std.mem.Allocator, context: Handler.RequestContext) void {
        context.app.env.deinit();
        allocator.destroy(context.app);
    }
    pub fn deinit(self: *TestSetup, allocator: std.mem.Allocator) void {
        self.user.deinit(allocator);
    }
};

const std = @import("std");
const pg = @import("pg");
const dotenv = @import("../util/dotenv.zig").dotenv;
const Database = @import("../db.zig");
const redis = @import("../util/redis.zig");
const Handler = @import("../handler.zig");

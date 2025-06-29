const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const redis = @import("../util/redis.zig");

const log = std.log.scoped(.auth_model);

const ACCESS_TOKEN_EXPIRY = 15 * 60;
const REFRESH_TOKEN_EXPIRY = 7 * 24 * 60 * 60;

pub const Auth = struct {
    allocator: std.mem.Allocator,
    access_token: []const u8,
    refresh_token: []const u8,
    expires_in: i32,

    pub fn deinit(self: *Auth) void {
        self.allocator.free(self.access_token);
        self.allocator.free(self.refresh_token);
    }

    pub const CreateProps = struct {
        allocator: std.mem.Allocator,
        database: *pg.Pool,
        jwt_secret: []const u8,
        redis_client: *redis.RedisClient,
    };
    pub fn create(props: CreateProps, request: rq.PostAuth) anyerror!Auth {
        var conn = try props.database.acquire();
        defer conn.release();
        var row = conn.row(SQL_STRINGS.create, //
            .{request.username}) catch |err| {
            if (conn.err) |pg_err| {
                log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
            }
            return err;
        } orelse return error.NotFound;
        defer row.deinit() catch {};
        const user_id = row.get(i32, 0);
        const hash = row.get([]u8, 1);
        const isValidPassword = try auth.verifyPassword(props.allocator, hash, request.password);
        const claims = auth.JWTClaims{ .user_id = user_id, .exp = std.time.milliTimestamp() + ACCESS_TOKEN_EXPIRY };

        if (!isValidPassword) return error.NotFound;
        const access_token = try auth.createJWT(props.allocator, claims, props.jwt_secret);

        const refresh_token = try auth.createSessionToken(props.allocator);

        const value = try std.fmt.allocPrint(props.allocator, "{}", .{user_id});
        defer props.allocator.free(value);

        _ = try props.redis_client.setWithExpiry(refresh_token, value, REFRESH_TOKEN_EXPIRY);

        return Auth{ .allocator = props.allocator, .access_token = access_token, .refresh_token = refresh_token, .expires_in = ACCESS_TOKEN_EXPIRY };
    }

    pub const RefreshProps = struct {
        allocator: std.mem.Allocator,
        redis_client: *redis.RedisClient,
        refresh_token: []const u8,
        jwt_secret: []const u8,
    };

    pub fn refresh(props: RefreshProps) anyerror!Auth {
        const result = props.redis_client.get(props.refresh_token) catch |err| switch (err) {
            error.KeyValuePairNotFound => return error.NotFound,
            else => return error.MiscError,
        };
        const number = try std.fmt.parseInt(i32, result, 10);
        const claims = auth.JWTClaims{ .user_id = number, .exp = std.time.milliTimestamp() + ACCESS_TOKEN_EXPIRY };

        const access_token = try auth.createJWT(props.allocator, claims, props.jwt_secret);

        return Auth{ .allocator = props.allocator, .access_token = access_token, .expires_in = ACCESS_TOKEN_EXPIRY, .refresh_token = props.refresh_token };
    }

    pub const InvalidateProps = struct {
        refresh_token: []const u8,
        redis_client: *redis.RedisClient,
    };

    pub fn invalidate(props: InvalidateProps) anyerror!bool {
        const response = try props.redis_client.delete(props.refresh_token);
        return if (std.mem.eql(u8, response, ":0")) false else true;
    }

    pub fn format(
        self: Auth,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("Auth{ ");
        try writer.print(".access_token = {s}, .expires_in = {d}, .refresh_token: {s}", .{ self.access_token, self.expires_in, self.refresh_token });
        try writer.writeAll(" }");
    }
};

const SQL_STRINGS = struct {
    pub const create = "SELECT id, password FROM users WHERE username=$1;";
};

const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Auth | Create" {
    //SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;
    const jwt = @import("jwt");
    var test_env = Tests.test_env;
    const test_name = "Auth | Create";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    const jwt_secret = test_env.env.get("JWT_SECRET").?;
    const props = Auth.CreateProps{
        .allocator = allocator,
        .database = test_env.database,
        .jwt_secret = jwt_secret,
        .redis_client = &test_env.redis_client,
    };

    const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
    defer allocator.free(password);

    // TEST
    var access_token: ?[]u8 = null;
    var refresh_token: ?[]u8 = null;
    defer {
        if (access_token) |token| allocator.free(token);
        if (refresh_token) |token| allocator.free(token);
    }

    // Create test
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        var create_response = Auth.create(props, .{
            .username = test_name,
            .password = password,
        }) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer create_response.deinit();

        access_token = try allocator.dupe(u8, create_response.access_token);
        refresh_token = try allocator.dupe(u8, create_response.refresh_token);

        var decoded = try jwt.decode(allocator, auth.JWTClaims, create_response.access_token, .{ .secret = jwt_secret }, .{});
        defer decoded.deinit();

        std.testing.expectEqual(setup.user.id, decoded.claims.user_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "Auth | Refresh" {
    //SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;

    var test_env = Tests.test_env;
    const test_name = "Auth | Refresh";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
    defer allocator.free(password);
    const jwt_secret = test_env.env.get("JWT_SECRET").?;
    const props = Auth.CreateProps{
        .allocator = allocator,
        .database = test_env.database,
        .jwt_secret = jwt_secret,
        .redis_client = &test_env.redis_client,
    };
    var create = try Auth.create(props, .{
        .username = test_name,
        .password = password,
    });
    defer create.deinit();
    const access_token = try allocator.dupe(u8, create.access_token);
    defer allocator.free(access_token);
    const refresh_token = try allocator.dupe(u8, create.refresh_token);
    defer allocator.free(refresh_token);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const refresh_props = Auth.RefreshProps{
            .allocator = allocator,
            .jwt_secret = jwt_secret,
            .redis_client = &test_env.redis_client,
            // duping here as the response.deinit() frees
            .refresh_token = try allocator.dupe(u8, refresh_token),
        };
        var refresh_response = Auth.refresh(refresh_props) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer refresh_response.deinit();

        std.testing.expectEqualStrings(refresh_response.refresh_token, refresh_token) catch |err| {
            benchmark.fail(err);
            return err;
        };

        const is_same_access_token = std.mem.eql(u8, refresh_response.access_token, access_token);
        std.testing.expect(!is_same_access_token) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "Auth | Invalidate" {
    //SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;

    var test_env = Tests.test_env;
    const test_name = "Auth | Invalidate";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
    defer allocator.free(password);
    const jwt_secret = test_env.env.get("JWT_SECRET").?;
    const props = Auth.CreateProps{
        .allocator = allocator,
        .database = test_env.database,
        .jwt_secret = jwt_secret,
        .redis_client = &test_env.redis_client,
    };
    var create = try Auth.create(props, .{
        .username = test_name,
        .password = password,
    });
    defer create.deinit();
    const access_token = try allocator.dupe(u8, create.access_token);
    defer allocator.free(access_token);
    const refresh_token = try allocator.dupe(u8, create.refresh_token);
    defer allocator.free(refresh_token);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const invalidate_response = Auth.invalidate(.{ .redis_client = &test_env.redis_client, .refresh_token = refresh_token }) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expect(invalidate_response) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

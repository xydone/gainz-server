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

test "create,refresh, invalidate auth token" {
    const jwt = @import("jwt");
    var test_env = Tests.test_env;

    const jwt_secret = test_env.env.get("JWT_SECRET").?;
    const props = Auth.CreateProps{ .allocator = test_env.allocator, .database = test_env.database, .jwt_secret = jwt_secret, .redis_client = &test_env.redis_client };

    const username = try std.fmt.allocPrint(test_env.allocator, "Testing username", .{});
    defer test_env.allocator.free(username);
    const password = try std.fmt.allocPrint(test_env.allocator, "Testing password", .{});
    defer test_env.allocator.free(password);

    var create_response = try Auth.create(props, .{ .username = username, .password = password });
    defer create_response.deinit();

    var decoded = try jwt.decode(test_env.allocator, auth.JWTClaims, create_response.access_token, .{ .secret = jwt_secret }, .{});
    defer decoded.deinit();

    try std.testing.expectEqual(1, decoded.claims.user_id);
    const refresh_props = Auth.RefreshProps{ .allocator = test_env.allocator, .jwt_secret = jwt_secret, .redis_client = &test_env.redis_client, .refresh_token = try test_env.allocator.dupe(u8, create_response.refresh_token) };
    var refresh_response = try Auth.refresh(refresh_props);
    defer refresh_response.deinit();

    try std.testing.expectEqualStrings(refresh_response.refresh_token, create_response.refresh_token);

    const is_same_access_token = std.mem.eql(u8, refresh_response.access_token, create_response.access_token);
    try std.testing.expect(!is_same_access_token);

    const duped_token = try test_env.allocator.dupe(u8, create_response.refresh_token);
    defer test_env.allocator.free(duped_token);
    const invalidate_response = try Auth.invalidate(.{ .redis_client = &test_env.redis_client, .refresh_token = duped_token });
    try std.testing.expect(invalidate_response);

    //check if the token is actually invalid
    const failing_refresh = Auth.refresh(refresh_props);

    try std.testing.expectError(error.NotFound, failing_refresh);
}

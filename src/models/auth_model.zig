const log = std.log.scoped(.auth_model);

const ACCESS_TOKEN_EXPIRY = 15 * 60;
const REFRESH_TOKEN_EXPIRY = 7 * 24 * 60 * 60;

inline fn generateAccessTokenExpiry() i64 {
    return std.time.timestamp() + ACCESS_TOKEN_EXPIRY;
}

pub const Create = struct {
    pub const Request = struct {
        username: []const u8,
        password: []const u8,
    };
    pub const Response = struct {
        access_token: []const u8,
        refresh_token: []const u8,
        expires_in: i32,

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            allocator.free(self.access_token);
            allocator.free(self.refresh_token);
        }
    };

    pub const Props = struct {
        allocator: std.mem.Allocator,
        database: *Pool,
        jwt_secret: []const u8,
        redis_client: *redis.RedisClient,
    };

    pub const Errors = error{
        CannotCreate,
        RedisError,
        UserNotFound,
        OutOfMemory,
    } || DatabaseErrors;
    pub fn call(props: Props, request: Request) Errors!Response {
        var conn = props.database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const error_handler = ErrorHandler{ .conn = conn };

        var row = conn.row(query_string, //
            .{request.username}) catch |err| {
            const error_data = error_handler.handle(err);
            if (error_data) |data| {
                ErrorHandler.printErr(data);
            }

            return error.CannotCreate;
        } orelse return error.UserNotFound;
        defer row.deinit() catch {};
        const user_id = row.get(i32, 0);
        const hash = row.get([]u8, 1);
        const isValidPassword = auth.verifyPassword(props.allocator, hash, request.password) catch return error.CannotCreate;
        const claims = auth.JWTClaims{ .user_id = user_id, .exp = generateAccessTokenExpiry() };

        if (!isValidPassword) return error.CannotCreate;
        const access_token = auth.createJWT(props.allocator, claims, props.jwt_secret) catch return error.CannotCreate;

        const refresh_token = auth.createSessionToken(props.allocator) catch return error.CannotCreate;

        const value = std.fmt.allocPrint(props.allocator, "{}", .{user_id}) catch return error.OutOfMemory;
        defer props.allocator.free(value);

        _ = props.redis_client.setWithExpiry(refresh_token, value, REFRESH_TOKEN_EXPIRY) catch return error.RedisError;

        return Response{
            .access_token = access_token,
            .refresh_token = refresh_token,
            .expires_in = ACCESS_TOKEN_EXPIRY,
        };
    }

    const query_string = "SELECT id, password FROM users WHERE username=$1;";
};

pub const Refresh = struct {
    pub const Props = struct {
        allocator: std.mem.Allocator,
        redis_client: *redis.RedisClient,
        refresh_token: []const u8,
        jwt_secret: []const u8,
    };
    pub const Response = struct {
        access_token: []const u8,
        refresh_token: []const u8,
        expires_in: i32,

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            allocator.free(self.access_token);
        }
    };

    pub const Errors = error{ CannotCreateJWT, UserNotFound, RedisError, ParseError };
    pub fn call(props: Props) Errors!Response {
        const result = props.redis_client.get(props.refresh_token) catch |err| switch (err) {
            error.KeyValuePairNotFound => return error.UserNotFound,
            else => return error.RedisError,
        };
        const number = std.fmt.parseInt(i32, result, 10) catch return error.ParseError;
        const claims = auth.JWTClaims{ .user_id = number, .exp = generateAccessTokenExpiry() };

        const access_token = auth.createJWT(props.allocator, claims, props.jwt_secret) catch return error.CannotCreateJWT;

        return Response{
            .access_token = access_token,
            .refresh_token = props.refresh_token,
            .expires_in = ACCESS_TOKEN_EXPIRY,
        };
    }
};

pub const Auth = struct {
    allocator: std.mem.Allocator,
    access_token: []const u8,
    refresh_token: []const u8,
    expires_in: i32,

    pub fn deinit(self: *Auth) void {
        self.allocator.free(self.access_token);
        self.allocator.free(self.refresh_token);
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

const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "API Auth | Create" {
    //SETUP
    const allocator = std.testing.allocator;
    const jwt = @import("jwt");
    var test_env = Tests.test_env;
    const test_name = "API Auth | Create";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const jwt_secret = test_env.env.get("JWT_SECRET").?;
    const props = Create.Props{
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
        var create_response = try Create.call(props, .{
            .username = test_name,
            .password = password,
        });
        defer create_response.deinit(allocator);

        access_token = try allocator.dupe(u8, create_response.access_token);
        refresh_token = try allocator.dupe(u8, create_response.refresh_token);

        var decoded = try jwt.decode(allocator, auth.JWTClaims, create_response.access_token, .{ .secret = jwt_secret }, .{});
        defer decoded.deinit();

        try std.testing.expectEqual(setup.user.id, decoded.claims.user_id);
    }
}

test "API Auth | Refresh" {
    //SETUP
    const allocator = std.testing.allocator;

    var test_env = Tests.test_env;
    const test_name = "API Auth | Refresh";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
    defer allocator.free(password);
    const jwt_secret = test_env.env.get("JWT_SECRET").?;
    const props = Create.Props{
        .allocator = allocator,
        .database = test_env.database,
        .jwt_secret = jwt_secret,
        .redis_client = &test_env.redis_client,
    };
    var create = try Create.call(props, .{
        .username = test_name,
        .password = password,
    });
    defer create.deinit(allocator);

    const access_token = try allocator.dupe(u8, create.access_token);
    defer allocator.free(access_token);
    const refresh_token = try allocator.dupe(u8, create.refresh_token);
    defer allocator.free(refresh_token);

    // TEST
    {
        const refresh_props = Refresh.Props{
            .allocator = allocator,
            .jwt_secret = jwt_secret,
            .redis_client = &test_env.redis_client,
            // duping here as the response.deinit() frees
            .refresh_token = try allocator.dupe(u8, refresh_token),
        };
        defer allocator.free(refresh_props.refresh_token);

        const refresh_response = try Refresh.call(refresh_props);
        defer refresh_response.deinit(allocator);

        try std.testing.expectEqualStrings(refresh_response.refresh_token, refresh_token);
    }
}

test "API Auth | Invalidate" {
    //SETUP
    const allocator = std.testing.allocator;

    var test_env = Tests.test_env;
    const test_name = "API Auth | Invalidate";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
    defer allocator.free(password);
    const jwt_secret = test_env.env.get("JWT_SECRET").?;
    const props = Create.Props{
        .allocator = allocator,
        .database = test_env.database,
        .jwt_secret = jwt_secret,
        .redis_client = &test_env.redis_client,
    };
    var create = try Create.call(props, .{
        .username = test_name,
        .password = password,
    });
    defer create.deinit(allocator);

    const access_token = try allocator.dupe(u8, create.access_token);
    defer allocator.free(access_token);
    const refresh_token = try allocator.dupe(u8, create.refresh_token);
    defer allocator.free(refresh_token);

    // TEST
    {
        const invalidate_response = try Auth.invalidate(.{ .redis_client = &test_env.redis_client, .refresh_token = refresh_token });
        try std.testing.expect(invalidate_response);
    }
}

const std = @import("std");

const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;

const Handler = @import("../handler.zig");
const auth = @import("../util/auth.zig");
const redis = @import("../util/redis.zig");

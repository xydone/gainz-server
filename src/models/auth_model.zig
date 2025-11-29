const log = std.log.scoped(.model);

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
        const isValidPassword = verifyPassword(props.allocator, hash, request.password) catch return error.CannotCreate;
        const claims = JWTClaims{ .user_id = user_id, .exp = generateAccessTokenExpiry() };

        if (!isValidPassword) return error.CannotCreate;
        const access_token = createJWT(props.allocator, claims, props.jwt_secret) catch return error.CannotCreate;

        const refresh_token = createSessionToken(props.allocator) catch return error.CannotCreate;

        const value = std.fmt.allocPrint(props.allocator, "{}", .{user_id}) catch return error.OutOfMemory;
        defer props.allocator.free(value);

        const response = props.redis_client.setWithExpiry(props.allocator, refresh_token, value, REFRESH_TOKEN_EXPIRY) catch return error.RedisError;
        defer props.allocator.free(response);

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
        const result = props.redis_client.get(props.allocator, props.refresh_token) catch |err| switch (err) {
            error.KeyValuePairNotFound => return error.UserNotFound,
            else => return error.RedisError,
        };
        defer props.allocator.free(result);
        const number = std.fmt.parseInt(i32, result, 10) catch return error.ParseError;
        const claims = JWTClaims{ .user_id = number, .exp = generateAccessTokenExpiry() };

        const access_token = createJWT(props.allocator, claims, props.jwt_secret) catch return error.CannotCreateJWT;

        return Response{
            .access_token = access_token,
            .refresh_token = props.refresh_token,
            .expires_in = ACCESS_TOKEN_EXPIRY,
        };
    }
};

pub const Invalidate = struct {
    // perhaps a bit pointless as if success can be returned, it is always successful.
    pub const Response = struct {
        success: bool,
    };
    pub const Props = struct {
        allocator: std.mem.Allocator,
        refresh_token: []const u8,
        redis_client: *redis.RedisClient,
    };

    pub fn call(props: Props) anyerror!bool {
        const response = try props.redis_client.delete(props.allocator, props.refresh_token);
        defer props.allocator.free(response);
        return if (std.mem.eql(u8, response, ":0")) false else true;
    }
};

// TODO: test this
// NOTE: currently this does not handle a potential collision and just errors. This *should* be unlikely though.
pub const CreateAPIKey = struct {
    pub const Response = struct {
        api_key: []const u8,

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            allocator.free(self.api_key);
        }
    };

    pub const Errors = error{ CannotCreate, UserNotFound } || DatabaseErrors;
    pub fn call(allocator: std.mem.Allocator, database: *Pool, user_id: i32) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const error_handler = ErrorHandler{ .conn = conn };

        const api_key = createAPIKey(allocator) catch return error.CannotCreate;

        const hashed_token = hashPassword(allocator, api_key) catch return error.CannotCreate;
        defer allocator.free(hashed_token);

        _ = conn.exec(query_string, //
            .{ user_id, hashed_token }) catch |err| {
            const error_data = error_handler.handle(err);
            if (error_data) |data| {
                ErrorHandler.printErr(data);
            }

            return error.CannotCreate;
        };

        return .{
            .api_key = api_key,
        };
    }
    const query_string =
        \\INSERT INTO auth.api_keys (user_id, token)
        \\VALUES ($1, $2);
    ;
};
const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "API | Create" {
    //SETUP
    const allocator = std.testing.allocator;
    const jwt = @import("jwt");
    var test_env = Tests.test_env;
    const test_name = "API | Create";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const jwt_secret = test_env.env.JWT_SECRET;
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

        var decoded = try jwt.decode(allocator, JWTClaims, create_response.access_token, .{ .secret = jwt_secret }, .{});
        defer decoded.deinit();

        try std.testing.expectEqual(setup.user.id, decoded.claims.user_id);
    }
}

test "API | Refresh" {
    //SETUP
    const allocator = std.testing.allocator;

    var test_env = Tests.test_env;
    const test_name = "API | Refresh";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
    defer allocator.free(password);
    const jwt_secret = test_env.env.JWT_SECRET;
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

test "API | Invalidate" {
    //SETUP
    const allocator = std.testing.allocator;

    var test_env = Tests.test_env;
    const test_name = "API | Invalidate";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
    defer allocator.free(password);
    const jwt_secret = test_env.env.JWT_SECRET;
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
        const invalidate_response = try Invalidate.call(.{
            .allocator = allocator,
            .redis_client = &test_env.redis_client,
            .refresh_token = refresh_token,
        });
        try std.testing.expect(invalidate_response);
    }
}

test "API | Create API Key" {
    //SETUP
    const allocator = std.testing.allocator;

    var test_env = Tests.test_env;
    const test_name = "API | Create API Key";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const password = try std.fmt.allocPrint(allocator, "Testing password", .{});
    defer allocator.free(password);
    const jwt_secret = test_env.env.JWT_SECRET;
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
        const response = try CreateAPIKey.call(allocator, test_env.database, setup.user.id);
        defer response.deinit(allocator);
    }
}

const std = @import("std");

const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;

const Handler = @import("../handler.zig");

const JWTClaims = @import("../util/auth.zig").JWTClaims;

const verifyPassword = @import("../util/auth.zig").verifyPassword;
const hashPassword = @import("../util/auth.zig").hashPassword;
const createJWT = @import("../util/auth.zig").createJWT;
const createSessionToken = @import("../util/auth.zig").createSessionToken;
const createAPIKey = @import("../util/auth.zig").createAPIKey;
const redis = @import("../util/redis.zig");

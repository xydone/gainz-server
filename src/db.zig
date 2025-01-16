const std = @import("std");

const pg = @import("pg");

const dotenv = @import("util/dotenv.zig");

const EnvErrors = error{
    NoDatabaseHost,
    NoDatabaseName,
    NoDatabaseUsername,
    NoDatabasePassword,
};

const log = std.log.scoped(.database);
pub fn init(allocator: std.mem.Allocator, env: dotenv) !*pg.Pool {
    const database_host = env.get("DATABASE_HOST") orelse {
        return EnvErrors.NoDatabaseHost;
    };
    const database_name = env.get("DATABASE_NAME") orelse {
        return EnvErrors.NoDatabaseName;
    };
    const database_password = env.get("DATABASE_PASSWORD") orelse {
        return EnvErrors.NoDatabasePassword;
    };
    const database_username = env.get("DATABASE_USERNAME") orelse {
        return EnvErrors.NoDatabaseUsername;
    };
    const pool = try pg.Pool.init(allocator, .{ .size = 5, .connect = .{
        .port = 5432,
        .host = database_host,
    }, .auth = .{
        .username = database_username,
        .database = database_name,
        .password = database_password,
        .timeout = 10_000,
    } });
    return pool;
}

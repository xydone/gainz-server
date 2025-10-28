pub const Pool = pg.Pool;
pub const DatabaseErrors = error{
    GenericDatabaseError,
    CannotAcquireConnection,
};

const log = std.log.scoped(.database);
pub fn init(allocator: std.mem.Allocator, env: dotenv) !*pg.Pool {
    const database_host = env.get("DATABASE_HOST") orelse {
        return error.NoDatabaseHost;
    };
    const database_name = env.get("DATABASE_NAME") orelse {
        return error.NoDatabaseName;
    };
    const database_password = env.get("DATABASE_PASSWORD") orelse {
        return error.NoDatabasePassword;
    };
    const database_username = env.get("DATABASE_USERNAME") orelse {
        return error.NoDatabaseUsername;
    };
    const database_port = try std.fmt.parseInt(u16, env.get("DATABASE_PORT") orelse "5432", 10);
    const pool = try pg.Pool.init(allocator, .{ .size = 5, .connect = .{
        .port = database_port,
        .host = database_host,
    }, .auth = .{
        .username = database_username,
        .database = database_name,
        .password = database_password,
        .timeout = 10_000,
    } });
    return pool;
}

pub const ErrorHandler = struct {
    conn: *pg.Conn,

    pub fn handle(self: ErrorHandler, err: anyerror) ?pg.Error {
        if (err == error.PG) {
            if (self.conn.err) |pge| {
                return pge;
            }
        }
        return null;
    }

    pub fn printErr(err: pg.Error) void {
        std.log.err("severity: {s} |code: {s} | failure: {s}", .{ err.severity, err.code, err.message });
    }
};

const std = @import("std");

const pg = @import("pg");

const dotenv = @import("util/dotenv.zig").dotenv;

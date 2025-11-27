pub const Pool = pg.Pool;
pub const DatabaseErrors = error{
    GenericDatabaseError,
    CannotAcquireConnection,
};

const log = std.log.scoped(.database);
pub fn init(allocator: std.mem.Allocator, env: Env) !*pg.Pool {
    const pool = try pg.Pool.init(allocator, .{ .size = 5, .connect = .{
        .port = env.DATABASE_PORT,
        .host = env.DATABASE_HOST,
    }, .auth = .{
        .username = env.DATABASE_USERNAME,
        .database = env.DATABASE_NAME,
        .password = env.DATABASE_PASSWORD,
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

const Env = @import("env.zig");

const std = @import("std");

const httpz = @import("httpz");
const pg = @import("pg");

const Auth = @import("./routes/auth.zig");
const db = @import("db.zig");
const Handler = @import("handler.zig");
const Entry = @import("routes/Entry.zig");
const Food = @import("routes/food.zig");
const User = @import("routes/user.zig");
const types = @import("types.zig");
const dotenv = @import("util/dotenv.zig");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

const log = std.log.scoped(.main);
const PORT = 3000;
pub fn main() !void {
    var env = try dotenv.init(allocator, ".env");
    defer env.deinit();
    _ = env.get("JWT_SECRET") orelse {
        log.err("The .env file is missing a \"JWT_SECRET\" parameter, please add it and try again!", .{});
        return;
    };
    const database = try db.init(allocator, env);

    defer database.deinit();

    var handler = Handler{ .allocator = allocator, .db = database, .env = env };

    var server = try httpz.Server(*Handler).init(allocator, .{ .port = PORT }, &handler);
    defer server.deinit();
    defer server.stop();

    const cors = try server.middleware(httpz.middleware.Cors, .{
        .origin = "*",
        //NOTE: review what headers I'm actually allowing
        .headers = "*",
    });
    const router = server.router(.{ .middlewares = &.{cors} });
    // /api/user
    User.init(router);
    // /api/food
    Food.init(router);
    // /api/auth
    Auth.init(router);

    log.info("listening http://localhost:{d}/", .{PORT});

    try server.listen();
}

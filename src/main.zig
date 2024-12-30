const std = @import("std");

const httpz = @import("httpz");
const pg = @import("pg");

const db = @import("db.zig");
const Handler = @import("handler.zig");
const Entry = @import("routes/Entry.zig");
const Food = @import("routes/food.zig");
const User = @import("routes/user.zig");
const types = @import("types.zig");

// var gpa = std.heap.GeneralPurposeAllocator(.{}){};
// var allocator = gpa.allocator();
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

const log = std.log.scoped(.main);
const PORT = 3000;

pub fn main() !void {
    const database = try db.init(allocator);

    defer database.deinit();

    var handler = Handler{ .allocator = allocator, .db = database };

    var server = try httpz.Server(*Handler).init(allocator, .{ .port = PORT }, &handler);
    defer server.deinit();
    defer server.stop();

    const cors = try server.middleware(httpz.middleware.Cors, .{
        .origin = "*",
        //NOTE: review what headers I'm actually allowing. Copy-paste from https://stackoverflow.com/questions/32500073/request-header-field-access-control-allow-headers-is-not-allowed-by-itself-in-pr
        .headers = "Origin, X-Requested-With, Content-Type, Accept, x-access-token",
    });
    const router = server.router(.{ .middlewares = &.{cors} });
    // /api/user
    User.init(router);
    // /api/food
    Food.init(router);

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});

    try server.listen();
}

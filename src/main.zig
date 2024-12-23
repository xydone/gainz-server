const std = @import("std");

const httpz = @import("httpz");
const pg = @import("pg");

const db = @import("db.zig");
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

    var app = types.App{
        .db = database,
        .allocator = allocator,
    };
    defer database.deinit();

    var server = try httpz.Server(*types.App).init(allocator, .{ .port = PORT }, &app);
    defer server.deinit();
    defer server.stop();
    var router = server.router(.{});

    // /api/user
    User.init(router);
    // /api/food
    Food.init(router);

    router.post("/api/food", Food.postFood, .{});
    std.debug.print("listening http://localhost:{d}/\n", .{PORT});

    try server.listen();
}

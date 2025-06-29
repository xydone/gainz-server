const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");

// ROUTES
const Auth = @import("auth.zig").init;
const Entry = @import("entry.zig").init;
const Food = @import("food.zig").init;
const User = @import("user.zig").init;
const Note = @import("note.zig").init;
const Exercise = @import("exercise/routes.zig").init;

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    // /api/user
    User(router);
    // /api/food
    Food(router);
    // /api/auth
    Auth(router);
    // /api/note
    Note(router);
    // /api/exercise
    Exercise(router);
}

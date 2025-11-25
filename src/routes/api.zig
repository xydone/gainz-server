pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    // /api/user
    User.init(router);
    // /api/food
    Food.init(router);
    // /api/auth
    Auth.init(router);
    // /api/note
    Note.init(router);
    // /api/exercise
    Exercise.init(router);
    // /api/exercise
    Workout.init(router);
    // /api/analytics
    Analytics.init(router);
}

const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");

// ROUTES
const Auth = @import("auth.zig");
const Entry = @import("entry.zig");
const Food = @import("food.zig");
const User = @import("user.zig");
const Note = @import("note.zig");
const Workout = @import("workout.zig");
const Exercise = @import("exercise/routes.zig");
const Analytics = @import("analytics//routes.zig");

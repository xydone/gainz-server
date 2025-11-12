const endpoint_list: []Handler.Endpoint = &.{
    User.endpoint_list,
    Food.endpoint_list,
    Auth.endpoint_list,
    Note.endpoint_list,
    Exercise.endpoint_list,
    Workout.endpoint_list,
};

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

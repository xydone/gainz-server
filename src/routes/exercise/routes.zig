const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");

const Exercise = @import("exercise.zig").init;
const Category = @import("category.zig").init;
const Unit = @import("unit.zig").init;
const Entry = @import("entry.zig").init;

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Exercise(router);
    Category(router);
    Unit(router);
    Entry(router);
}

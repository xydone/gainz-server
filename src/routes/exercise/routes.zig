const endpoint_list: []Handler.EndpointData = .{
    Exercise.endpoint_data,
    Category.endpoint_data,
    Unit.endpoint_data,
    Entry.endpoint_data,
};

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Exercise.init(router);
    Category.init(router);
    Unit.init(router);
    Entry.init(router);
}

const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");

const Exercise = @import("exercise.zig");
const Category = @import("category.zig");
const Unit = @import("unit.zig");
const Entry = @import("entry.zig");

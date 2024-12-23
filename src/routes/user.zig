const std = @import("std");

const httpz = @import("httpz");

const db = @import("../db.zig");
const rq = @import("../request.zig");
const types = @import("../types.zig");
const Weight = @import("./measurement.zig");
const Entry = @import("entry.zig");

const log = std.log.scoped(.users);

pub fn init(router: *httpz.Router(*types.App, *const fn (*types.App, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    router.*.post("/api/user", postUser, .{});

    //subroutes
    // /api/user/entry
    Entry.init(router);
    // /api/user/weight
    Weight.init(router);
}

// fn getUser(app: *types.App, req: *httpz.Request, res: *httpz.Response) void {}

pub fn postUser(app: *types.App, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const user: ?std.json.Parsed(rq.UserRequest) = std.json.parseFromSlice(rq.UserRequest, app.allocator, body, .{}) catch {
            //handle return in some way
            return;
        };
        const result = db.createUser(app, user.?.value.display_name) catch {
            //TODO: error handling later
            res.status = 500;
            res.body = "Error encountered";
            return;
        };
        try res.json(result, .{});
    }
}

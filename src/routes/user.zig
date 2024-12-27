const std = @import("std");

const httpz = @import("httpz");

const db = @import("../db.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const types = @import("../types.zig");
const Measurement = @import("./measurement.zig");
const Entry = @import("entry.zig");

const log = std.log.scoped(.users);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    router.*.post("/api/user", createUser, .{});

    //subroutes
    // /api/user/entry
    Entry.init(router);
    // /api/user/weight
    Measurement.init(router);
}

// fn getUser(app: *types.App, req: *httpz.Request, res: *httpz.Response) void {}

pub fn createUser(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const user: ?std.json.Parsed(rq.UserRequest) = std.json.parseFromSlice(rq.UserRequest, ctx.app.allocator, body, .{}) catch {
            //handle return in some way
            return;
        };
        const result = db.createUser(ctx, user.?.value.display_name) catch {
            //TODO: error handling later
            res.status = 500;
            res.body = "Error encountered";
            return;
        };
        try res.json(result, .{});
    }
}

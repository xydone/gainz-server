const std = @import("std");

const httpz = @import("httpz");

const UserModel = @import("../models/users_model.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const types = @import("../types.zig");
const Measurement = @import("./measurement.zig");
const NoteEntries = @import("note_entries.zig");
const Entry = @import("entry.zig");

const log = std.log.scoped(.users);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    router.*.post("/api/user", createUser, .{});

    //subroutes
    // /api/user/entry
    Entry.init(router);
    // /api/user/measurement
    Measurement.init(router);
    // /api/user/notes
    NoteEntries.init(router);
}

pub fn createUser(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    if (req.body()) |body| {
        const user = std.json.parseFromSliceLeaky(rq.PostUser, ctx.app.allocator, body, .{}) catch {
            res.status = 400;
            res.body = "Body does not match requirements!";
            return;
        };
        const result = UserModel.create(ctx, user) catch {
            //TODO: error handling later
            res.status = 500;
            res.body = "Error encountered";
            return;
        };
        try res.json(result, .{});
    }
}

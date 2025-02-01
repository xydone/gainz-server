const std = @import("std");

const httpz = @import("httpz");

const UserModel = @import("../models/users_model.zig");
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
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
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const user = std.json.parseFromSliceLeaky(rq.PostUser, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    const result = UserModel.create(ctx, user) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    res.status = 200;
    try res.json(result, .{});
}

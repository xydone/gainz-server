const std = @import("std");

const httpz = @import("httpz");
const pg = @import("pg");

const types = @import("types.zig");

allocator: std.mem.Allocator,
db: *pg.Pool,
const Handler = @This();
const log = std.log.scoped(.handler);

pub const RouteData = struct {
    restricted: bool,
};

pub const RequestContext = struct {
    app: *Handler,
    user_id: i32,
};

pub fn dispatch(self: *Handler, action: httpz.Action(*RequestContext), req: *httpz.Request, res: *httpz.Response) !void {
    const user_id = req.header("x-access-token");
    if (req.route_data) |rd| {
        const route_data: *const RouteData = @ptrCast(@alignCast(rd));
        if (route_data.restricted and (user_id == null or user_id.?.len == 0)) {
            res.status = 401;
            res.body = "Permission denied!";
            return;
        }
    }
    var ctx = RequestContext{
        .app = self,
        .user_id = try std.fmt.parseInt(i32, user_id.?, 10),
    };

    try action(&ctx, req, res);
}

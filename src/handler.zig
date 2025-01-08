const std = @import("std");

const httpz = @import("httpz");
const jwt = @import("jwt");
const pg = @import("pg");

const types = @import("types.zig");
const auth = @import("util/auth.zig");
const dotenv = @import("util/dotenv.zig");

allocator: std.mem.Allocator,
db: *pg.Pool,
env: dotenv,
const Handler = @This();
const log = std.log.scoped(.handler);

pub const RouteData = struct {
    restricted: bool,
};

pub const RequestContext = struct {
    app: *Handler,
    user_id: ?i32,
};

pub fn dispatch(self: *Handler, action: httpz.Action(*RequestContext), req: *httpz.Request, res: *httpz.Response) !void {
    const token = req.header("x-access-token");
    var ctx = RequestContext{
        .app = self,
        .user_id = null,
    };

    if (req.route_data) |rd| {
        const route_data: *const RouteData = @ptrCast(@alignCast(rd));
        if (route_data.restricted and (token == null or token.?.len == 0)) {
            res.status = 401;
            res.body = "Permission denied!";
            return;
        }
        const decoded = jwt.decode(
            self.allocator,
            auth.JWTClaims,
            token.?,
            .{ .secret = self.env.get("JWT_SECRET").? },
            .{},
        ) catch |err| {
            log.warn("JWT Error: {s}", .{@errorName(err)});
            res.status = 401;
            res.body = "Invalid JWT, permission denied!";
            return;
        };
        ctx.user_id = decoded.claims.user_id;
    }

    try action(&ctx, req, res);
}

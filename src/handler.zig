const std = @import("std");

const httpz = @import("httpz");
const jwt = @import("jwt");
const pg = @import("pg");

const types = @import("types.zig");
const auth = @import("util/auth.zig");
const dotenv = @import("util/dotenv.zig");
const redis = @import("util/redis.zig");

allocator: std.mem.Allocator,
db: *pg.Pool,
env: dotenv,
redis_client: *redis.RedisClient,
const Handler = @This();
const log = std.log.scoped(.handler);

pub const RouteData = struct {
    restricted: bool = false,
    refresh: bool = false,
};

pub const RequestContext = struct {
    app: *Handler,
    user_id: ?i32,
    refresh_token: ?[]const u8,
};

pub fn dispatch(self: *Handler, action: httpz.Action(*RequestContext), req: *httpz.Request, res: *httpz.Response) !void {
    const access_token = req.header("x-access-token");
    const refresh_token = req.header("x-refresh-token");

    var ctx = RequestContext{ .app = self, .user_id = null, .refresh_token = null };

    if (req.route_data) |rd| {
        const route_data: *const RouteData = @ptrCast(@alignCast(rd));
        if (route_data.restricted) {
            if (access_token == null or access_token.?.len == 0) {
                res.status = 401;
                res.body = "Permission denied!";
                return;
            }
            const decoded = jwt.decode(
                self.allocator,
                auth.JWTClaims,
                access_token.?,
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
        if (route_data.refresh) {
            if (refresh_token == null or refresh_token.?.len == 0) {
                res.status = 401;
                res.body = "Permission denied!";
                return;
            }
            ctx.refresh_token = refresh_token;
        }
    }

    try action(&ctx, req, res);
}

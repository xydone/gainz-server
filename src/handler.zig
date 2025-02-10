const std = @import("std");

const httpz = @import("httpz");
const jwt = @import("jwt");
const pg = @import("pg");
const rs = @import("response.zig");
const rq = @import("request.zig");

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
    var access_token = req.header("authorization");
    const prefix = "Bearer ";

    var ctx = RequestContext{ .app = self, .user_id = null, .refresh_token = null };

    if (req.route_data) |rd| {
        const route_data: *const RouteData = @ptrCast(@alignCast(rd));
        if (route_data.restricted) {
            if (access_token == null or access_token.?.len == 0 or !std.mem.startsWith(u8, access_token.?, prefix)) {
                res.status = 401;
                res.body = "Permission denied!";
                return;
            }
            access_token = access_token.?[prefix.len..];
            const decoded = jwt.decode(
                self.allocator,
                auth.JWTClaims,
                access_token.?,
                .{ .secret = self.env.get("JWT_SECRET").? },
                //NOTE: there is a leeway by default in the validation struct
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
            const body = req.body() orelse {
                try rs.handleResponse(res, rs.ResponseError.body_missing, null);
                return;
            };
            const json = std.json.parseFromSliceLeaky(rq.RefreshAccessToken, ctx.app.allocator, body, .{}) catch {
                try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
                return;
            };
            ctx.refresh_token = json.refresh_token;
        }
    }

    try action(&ctx, req, res);
}

const std = @import("std");

const httpz = @import("httpz");
const jwt = @import("jwt");
const pg = @import("pg");
const handleResponse = @import("response.zig").handleResponse;
const ResponseError = @import("response.zig").ResponseError;

const types = @import("types.zig");
const auth = @import("util/auth.zig");
const dotenv = @import("util/dotenv.zig").dotenv;
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

const RefreshAccessToken = struct {
    refresh_token: []const u8,
};

pub fn dispatch(self: *Handler, action: httpz.Action(*RequestContext), req: *httpz.Request, res: *httpz.Response) !void {
    var timer = try std.time.Timer.start();

    var ctx = RequestContext{ .app = self, .user_id = null, .refresh_token = null };

    verifyToken(req, res, &ctx) catch {
        return try Logging.print(Logging{
            .allocator = self.allocator,
            .req = req.*,
            .res = res.*,
            .timer = &timer,
            .url_path = req.url.path,
        });
    };

    try action(&ctx, req, res);

    try Logging.print(Logging{
        .allocator = self.allocator,
        .req = req.*,
        .res = res.*,
        .timer = &timer,
        .url_path = req.url.path,
    });
}

fn verifyToken(req: *httpz.Request, res: *httpz.Response, ctx: *RequestContext) !void {
    var access_token = req.header("authorization");
    const prefix = "Bearer ";

    if (req.route_data) |rd| {
        const route_data: *const RouteData = @ptrCast(@alignCast(rd));
        if (route_data.restricted) {
            if (access_token == null or access_token.?.len == 0 or !std.mem.startsWith(u8, access_token.?, prefix)) {
                res.status = 401;
                res.body = "Permission denied!";
                return error.InvalidToken;
            }
            access_token = access_token.?[prefix.len..];
            var decoded = jwt.decode(
                ctx.app.allocator,
                auth.JWTClaims,
                access_token.?,
                .{ .secret = ctx.app.env.get("JWT_SECRET").? },
                //NOTE: there is a leeway by default in the validation struct
                .{},
            ) catch {
                res.status = 401;
                res.body = "Invalid JWT, permission denied!";
                return error.InvalidJWT;
            };
            defer decoded.deinit();
            ctx.user_id = decoded.claims.user_id;
        }
        if (route_data.refresh) {
            const body = req.body() orelse {
                try handleResponse(res, .body_missing, null);
                return error.MissingBody;
            };
            const json = std.json.parseFromSliceLeaky(RefreshAccessToken, ctx.app.allocator, body, .{}) catch {
                try handleResponse(res, ResponseError.body_missing_fields, null);
                return error.InvalidBodyJSON;
            };
            ctx.refresh_token = json.refresh_token;
        }
    }
}

const zdt = @import("zdt");

const Logging = struct {
    allocator: std.mem.Allocator,
    timer: *std.time.Timer,
    req: httpz.Request,
    res: httpz.Response,
    url_path: []const u8,
    pub fn print(self: Logging) !void {
        const time = self.timer.read();
        const locale = try zdt.Timezone.tzLocal(self.allocator);
        const now = try zdt.Datetime.now(.{ .tz = &locale });
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        // https://github.com/FObersteiner/zdt/wiki/String-parsing-and-formatting-directives
        try now.toString("[%Y-%m-%d %H:%M:%S]", buf.writer());
        const datetime = try buf.toOwnedSlice();
        std.debug.print("{s} {s} {s} {s}{d}\x1b[0m in {d:.2}ms ({d}ns)\n", .{
            datetime,
            @tagName(self.req.method),
            self.url_path,
            //ansi coloring (https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797)
            switch (self.res.status / 100) {
                //green
                2 => "\x1b[32m",
                //red
                4 => "\x1b[31m",
                // if its not a 2XX or 3XX, yellow
                else => "\x1b[33m",
            },
            self.res.status,
            //in ms
            @as(f64, @floatFromInt(time)) / std.time.ns_per_ms,
            //in nanoseconds
            time,
        });
    }
};

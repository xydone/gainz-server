allocator: std.mem.Allocator,
db: *pg.Pool,
env: Env,
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

    authenticateRequest(&ctx, req, res) catch {
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

fn authenticateRequest(ctx: *RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    const access_token = req.header("authorization");
    const api_key = req.header("x-api-key");
    if (req.route_data) |rd| {
        const route_data: *const RouteData = @ptrCast(@alignCast(rd));
        if (route_data.restricted) {
            if (api_key) |key| {
                verifyAPIKey(ctx, key) catch {
                    handleResponse(res, .unauthorized, "Permission denied!");
                    return error.AuthenticationFailed;
                };
            } else if (access_token) |token| {
                verifyJWT(ctx.app.allocator, ctx, token) catch |err| {
                    switch (err) {
                        error.InvalidToken => {
                            handleResponse(res, .unauthorized, "Permission denied!");
                            return error.AuthenticationFailed;
                        },
                        error.InvalidJWT => {
                            handleResponse(res, .unauthorized, "Permission denied!");
                            return error.AuthenticationFailed;
                        },
                    }
                };
            } else {
                handleResponse(res, .unauthorized, "Permission denied!");
                return error.AuthenticationFailed;
            }
        }
        if (route_data.refresh) {
            verifyRefresh(ctx, req) catch |err| switch (err) {
                error.MissingBody => {
                    handleResponse(res, .body_missing, null);
                    return error.AuthenticationFailed;
                },
                error.InvalidBodyJSON => {
                    handleResponse(res, .body_missing_fields, null);
                    return error.AuthenticationFailed;
                },
            };
        }
    }
}

fn verifyJWT(allocator: std.mem.Allocator, ctx: *RequestContext, access_token: []const u8) error{ InvalidJWT, InvalidToken }!void {
    const prefix = "Bearer ";
    if (access_token.len == 0 or !std.mem.startsWith(u8, access_token, prefix)) {
        return error.InvalidToken;
    }
    const token = access_token[prefix.len..];
    var decoded = jwt.decode(
        allocator,
        auth.JWTClaims,
        token,
        .{ .secret = ctx.app.env.JWT_SECRET },
        //NOTE: there is a leeway by default in the validation struct
        .{},
    ) catch {
        return error.InvalidJWT;
    };
    defer decoded.deinit();

    ctx.user_id = decoded.claims.user_id;
}

fn verifyRefresh(ctx: *RequestContext, req: *httpz.Request) error{ MissingBody, InvalidBodyJSON }!void {
    const body = req.body() orelse {
        return error.MissingBody;
    };
    const json = std.json.parseFromSliceLeaky(RefreshAccessToken, ctx.app.allocator, body, .{}) catch {
        return error.InvalidBodyJSON;
    };
    ctx.refresh_token = json.refresh_token;
}

fn verifyAPIKey(ctx: *RequestContext, api_key: []const u8) error{CannotGet}!void {
    const id = GetUserByAPIKey.call(ctx.app.db, api_key) catch return error.CannotGet;
    ctx.user_id = id;
}

pub const Router = httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void);

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

        var writer = std.Io.Writer.Allocating.init(self.allocator);
        defer writer.deinit();
        // https://github.com/FObersteiner/zdt/wiki/String-parsing-and-formatting-directives
        try now.toString("[%Y-%m-%d %H:%M:%S]", &writer.writer);
        const datetime = try writer.toOwnedSlice();
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

const std = @import("std");

const httpz = @import("httpz");
const jwt = @import("jwt");
const pg = @import("pg");
const handleResponse = @import("response.zig").handleResponse;
const ResponseError = @import("response.zig").ResponseError;

const GetUserByAPIKey = @import("models/auth_model.zig").GetUserByAPIKey;

const types = @import("types.zig");
const auth = @import("util/auth.zig");
const Env = @import("env.zig");
const redis = @import("util/redis.zig");

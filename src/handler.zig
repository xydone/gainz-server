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

pub const Router = httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void);

pub const EndpointRequestType = struct {
    Body: type = void,
    Params: type = void,
    Query: type = void,
};

pub fn EndpointRequest(comptime Body: type, comptime Params: type, comptime Query: type) type {
    return struct {
        body: Body,
        params: Params,
        query: Query,
    };
}

pub const EndpointData = struct {
    Request: EndpointRequestType,
    Response: type,
    path: []const u8,
    method: httpz.Method,
    route_data: RouteData,
    config: RouteData = .{},
};

pub fn Endpoint(
    comptime T: type,
) type {
    return struct {
        pub const endpoint_data: EndpointData = T.endpoint_data;
        const callImpl: *const fn (*Handler.RequestContext, T.Request, *httpz.response.Response) anyerror!void = T.call;

        pub fn init(router: *Router) void {
            const path = T.endpoint_data.path;
            const route_data = T.endpoint_data.route_data;
            switch (T.endpoint_data.method) {
                .GET => {
                    router.*.get(path, call, .{ .data = &route_data });
                },
                .POST => {
                    router.*.post(path, call, .{ .data = &route_data });
                },
                .PATCH => {
                    router.*.post(path, call, .{ .data = &route_data });
                },
                .PUT => {
                    router.*.post(path, call, .{ .data = &route_data });
                },
                .OPTIONS => {
                    router.*.post(path, call, .{ .data = &route_data });
                },
                .CONNECT => {
                    router.*.post(path, call, .{ .data = &route_data });
                },
                .DELETE => {
                    router.*.post(path, call, .{ .data = &route_data });
                },
                .HEAD => {
                    router.*.post(path, call, .{ .data = &route_data });
                },
                // NOTE: http.zig supports non-standard http methods. For now, creating routes with a non-standard method is not supported.
                .OTHER => {
                    @compileError("Method OTHER is not supported!");
                },
            }
        }

        pub fn call(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
            const allocator = res.arena;
            const request: EndpointRequest(T.endpoint_data.Request.Body, T.endpoint_data.Request.Params, T.endpoint_data.Request.Query) = .{
                .body = blk: {
                    switch (@typeInfo(T.endpoint_data.Request.Body)) {
                        .void => break :blk {},
                        else => {
                            const body = req.body() orelse {
                                try handleResponse(res, ResponseError.body_missing, null);
                                return;
                            };
                            break :blk std.json.parseFromSliceLeaky(T.endpoint_data.Request.Body, allocator, body, .{}) catch {
                                try handleResponse(res, ResponseError.not_found, null);
                                return;
                            };
                        },
                    }
                },

                .params = blk: {
                    switch (@typeInfo(T.endpoint_data.Request.Params)) {
                        .void => {},
                        else => |type_info| {
                            var params: T.endpoint_data.Request.Params = undefined;
                            inline for (type_info.@"struct".fields) |field| {
                                const value = req.param(field.name) orelse {
                                    const msg = try std.fmt.allocPrint(allocator, "{s} not found inside parameters!", .{field.name});
                                    defer allocator.free(msg);
                                    return try handleResponse(res, ResponseError.bad_request, msg);
                                };
                                switch (field.type) {
                                    u16, u32, u64 => |t| @field(params, field.name) = try std.fmt.parseInt(t, value, 10),
                                    f16, f32, f64 => |t| @field(params, field.name) = try std.fmt.parseFloat(
                                        t,
                                    ),
                                    []const u8, []u8 => @field(params, field.name) = value,
                                    else => |t| @compileError(std.fmt.comptimePrint("{} not supported!", .{t})),
                                }
                            }
                            break :blk params;
                        },
                    }
                },

                .query = blk: {
                    switch (@typeInfo(T.endpoint_data.Request.Query)) {
                        .void => {},
                        else => |type_info| {
                            var query: T.endpoint_data.Request.Query = undefined;
                            inline for (type_info.@"struct".fields) |field| {
                                var q = try req.query();
                                const value = q.get(field.name) orelse {
                                    const msg = try std.fmt.allocPrint(allocator, "{s} not found inside query!", .{field.name});
                                    defer allocator.free(msg);
                                    return try handleResponse(res, ResponseError.bad_request, msg);
                                };
                                switch (field.type) {
                                    u16, u32, u64 => |t| @field(query, field.name) = try std.fmt.parseInt(t, value, 10),
                                    f16, f32, f64 => |t| @field(query, field.name) = try std.fmt.parseFloat(t, value),
                                    []const u8, []u8 => @field(query, field.name) = value,
                                    else => |t| {
                                        switch (@typeInfo(t)) {
                                            .@"enum" => @field(query, field.name) = std.meta.stringToEnum(t, value) orelse {
                                                const enum_name = enum_blk: {
                                                    const name = @typeName(t);
                                                    // filter out the namespace that gets included inside the @typeInfo() response
                                                    // exit early if type does not have a namespace
                                                    const i = std.mem.lastIndexOfScalar(u8, name, '.') orelse break :enum_blk name;
                                                    break :enum_blk name[i + 1 ..];
                                                };
                                                const msg = try std.fmt.allocPrint(allocator, "Incorrect value '{s}' for enum {s}", .{ value, enum_name });
                                                defer allocator.free(msg);
                                                return try handleResponse(res, ResponseError.bad_request, msg);
                                            },
                                            else => @compileError(std.fmt.comptimePrint("{} not supported!", .{t})),
                                        }
                                    },
                                }
                            }

                            break :blk query;
                        },
                    }
                },
            };

            try T.call(ctx, request, res);
        }
    };
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

const types = @import("types.zig");
const auth = @import("util/auth.zig");
const dotenv = @import("util/dotenv.zig").dotenv;
const redis = @import("util/redis.zig");

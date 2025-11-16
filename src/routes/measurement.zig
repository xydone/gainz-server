const log = std.log.scoped(.measurement);

pub const endpoint_data = [_]EndpointData{
    Create.endpoint_data,
    Get.endpoint_data,
    GetRange.endpoint_data,
    GetRecent.endpoint_data,
};

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Create.init(router);
    Get.init(router);
    GetRange.init(router);
    GetRecent.init(router);
}

pub const Get = Endpoint(struct {
    const Params = GetModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = GetModel.Response,
        .method = .GET,
        .path = "/api/user/measurement/:measurement_id",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const response = GetModel.call(ctx.user_id.?, ctx.app.db, request.params) catch |err| switch (err) {
            error.NotFound => {
                handleResponse(res, ResponseError.unauthorized, null);
                return;
            },
            else => {
                handleResponse(res, ResponseError.not_found, null);
                return;
            },
        };

        try res.json(response, .{});
        return;
    }
});

const GetRange = Endpoint(struct {
    const Query = GetRangeModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Query = Query,
        },
        .Response = GetRangeModel.Response,
        .method = .GET,
        .path = "/api/user/measurement/",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, void, Query), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;

        const measurements = GetRangeModel.call(ctx.user_id.?, allocator, ctx.app.db, request.query) catch {
            handleResponse(res, ResponseError.not_found, null);
            return;
        };
        defer allocator.free(measurements);
        res.status = 200;
        try res.json(measurements, .{});
    }
});

const GetRecent = Endpoint(struct {
    const Query = GetRecentModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Query = Query,
        },
        .Response = GetRecentModel.Response,
        .method = .GET,
        .path = "/api/user/measurement/recent",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, void, Query), res: *httpz.Response) anyerror!void {
        const measurements = GetRecentModel.call(ctx.user_id.?, ctx.app.db, request.query) catch {
            handleResponse(res, ResponseError.not_found, null);
            return;
        };
        res.status = 200;
        try res.json(measurements, .{});
    }
});
const Create = Endpoint(struct {
    const Body = CreateModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = CreateModel.Response,
        .method = .POST,
        .path = "/api/user/measurement",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const result = CreateModel.call(ctx.user_id.?, ctx.app.db, request.body) catch {
            handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        res.status = 200;
        try res.json(result, .{});
    }
});

const std = @import("std");

const httpz = @import("httpz");

const GetModel = @import("../models/measurements_model.zig").Get;
const GetRangeModel = @import("../models/measurements_model.zig").GetInRange;
const GetRecentModel = @import("../models/measurements_model.zig").GetRecent;
const CreateModel = @import("../models/measurements_model.zig").Create;

const Handler = @import("../handler.zig");
const ResponseError = @import("../response.zig").ResponseError;
const handleResponse = @import("../response.zig").handleResponse;
const types = @import("../types.zig");

const Endpoint =@import("../endpoint.zig").Endpoint;
const EndpointRequest =@import("../endpoint.zig").EndpointRequest;
const EndpointData =@import("../endpoint.zig").EndpointData;

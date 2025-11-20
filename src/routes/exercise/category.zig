pub const endpoint_data = [_]EndpointData{
    Get.endpoint_data,
    Create.endpoint_data,
};

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Get.init(router);
    Create.init(router);
}

pub const Get = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{},
        .Response = GetModel.Response,
        .method = .GET,
        .path = "/api/exercise/category",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, _: EndpointRequest(void, void, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const categories = GetModel.call(allocator, ctx.user_id.?, ctx.app.db) catch {
            handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        allocator.free(categories);
        res.status = 200;
        try res.json(categories, .{});
    }
});

pub const Create = Endpoint(struct {
    const Body = CreateModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = CreateModel.Response,
        .method = .POST,
        .path = "/api/exercise/category",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const response = CreateModel.call(res.arena, ctx.user_id.?, ctx.app.db, request.body) catch {
            handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        res.status = 200;

        try res.json(response, .{});
    }
});
const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");
const handleResponse = @import("../../response.zig").handleResponse;
const ResponseError = @import("../../response.zig").ResponseError;

const types = @import("../../types.zig");
const CreateModel = @import("../../models/exercise/category.zig").Create;
const GetModel = @import("../../models/exercise/category.zig").Get;

const Endpoint = @import("../../endpoint.zig").Endpoint;
const EndpointRequest = @import("../../endpoint.zig").EndpointRequest;
const EndpointData = @import("../../endpoint.zig").EndpointData;

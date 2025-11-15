pub const endpoint_data = [_]EndpointData{
    GetAll.endpoint_data,
    Create.endpoint_data,
};

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    GetAll.init(router);
    Create.init(router);
}

const GetAll = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{},
        .Response = GetAllModel.Response,
        .method = .GET,
        .path = "/api/exercise/",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, _: EndpointRequest(void, void, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const exercises = GetAllModel.call(allocator, ctx.user_id.?, ctx.app.db) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        defer allocator.free(exercises);
        res.status = 200;
        try res.json(exercises, .{});
    }
});
const Create = Endpoint(struct {
    const Body = CreateModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = GetAllModel.Response,
        .method = .POST,
        .path = "/api/exercise/",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const exercise = CreateModel.call(ctx.user_id.?, ctx.app.db, request.body) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        res.status = 200;

        return res.json(exercise, .{});
    }
});
const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");
const handleResponse = @import("../../response.zig").handleResponse;
const ResponseError = @import("../../response.zig").ResponseError;

const CreateModel = @import("../../models/exercise/exercise.zig").Create;
const GetAllModel = @import("../../models/exercise/exercise.zig").GetAll;

const Endpoint = @import("../../handler.zig").Endpoint;
const EndpointRequest = @import("../../handler.zig").EndpointRequest;
const EndpointData = @import("../../handler.zig").EndpointData;

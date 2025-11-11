const log = std.log.scoped(.users);

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Create.init(router);
    Get.init(router);
    // router.*.post("/api/note", postNote, .{ .data = &RouteData });
    // router.*.get("/api/note/:note_id", getNote, .{ .data = &RouteData });
}

const Get = Endpoint(struct {
    const Params = GetModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = GetModel.Response,
        .method = .GET,
        .path = "/api/note/:note_id",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const result = GetModel.call(ctx, request.params) catch |err| switch (err) {
            error.NotFound => {
                try handleResponse(res, ResponseError.not_found, null);
                return;
            },
            else => {
                try handleResponse(res, ResponseError.internal_server_error, null);
                return;
            },
        };
        res.status = 200;
        try res.json(result, .{});
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
        .path = "/api/note/",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const result = CreateModel.call(ctx, request.body) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        res.status = 200;
        try res.json(result, .{});
    }
});

const std = @import("std");

const httpz = @import("httpz");

const CreateModel = @import("../models/note_model.zig").Create;
const GetModel = @import("../models/note_model.zig").Get;
const Handler = @import("../handler.zig");
const handleResponse = @import("../response.zig").handleResponse;
const ResponseError = @import("../response.zig").ResponseError;

const Endpoint = @import("../handler.zig").Endpoint;
const EndpointRequest = @import("../handler.zig").EndpointRequest;
const EndpointData = @import("../handler.zig").EndpointData;

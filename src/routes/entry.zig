const log = std.log.scoped(.entry);

pub const endpoint_data = [_]EndpointData{
    Create.endpoint_data,
    Get.endpoint_data,
    Delete.endpoint_data,
    Edit.endpoint_data,
    GetRecent.endpoint_data,
    GetAverage.endpoint_data,
    GetBreakdown.endpoint_data,
    GetRange.endpoint_data,
};

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Create.init(router);
    Get.init(router);
    Delete.init(router);
    Edit.init(router);
    GetRecent.init(router);
    GetAverage.init(router);
    GetBreakdown.init(router);
    GetRange.init(router);
}

const Get = Endpoint(struct {
    const Params = GetModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = GetModel.Request,
        },
        .Response = GetModel.Response,
        .method = .GET,
        .path = "/api/user/entry/:entry_id",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const response = GetModel.call(ctx.user_id.?, ctx.app.db, request.params) catch {
            handleResponse(res, ResponseError.not_found, null);
            return;
        };
        res.status = 200;

        try res.json(response, .{});
    }
});

const Delete = Endpoint(struct {
    const Params = DeleteModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = DeleteModel.Response,
        .method = .DELETE,
        .path = "/api/user/entry/:entry_id",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        DeleteModel.call(ctx.app.db, request.params) catch {
            handleResponse(res, ResponseError.not_found, "Cannot find an entry with this ID.");
            return;
        };
        res.status = 200;
    }
});
pub const Edit = Endpoint(struct {
    const Body = EditModel.Request;
    const Params = struct { entry_id: u32 };

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
            .Params = Params,
        },
        .Response = EditModel.Response,
        .method = .PUT,
        .path = "/api/user/entry/:entry_id",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, Params, void), res: *httpz.Response) anyerror!void {
        EditModel.call(ctx.app.db, request.body, request.params.entry_id) catch {
            handleResponse(res, ResponseError.not_found, "Cannot find an entry with this ID.");
            return;
        };
        res.status = 200;
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
        .path = "/api/user/entry/recent",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, void, Query), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const result = GetRecentModel.call(allocator, ctx.user_id.?, ctx.app.db, request.query) catch {
            handleResponse(res, ResponseError.not_found, null);
            return;
        };
        defer {
            for (result) |entry| {
                entry.deinit(allocator);
            }
            allocator.free(result);
        }
        res.status = 200;

        try res.json(result, .{});
    }
});

const GetAverage = Endpoint(struct {
    const Query = GetAverageModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Query = Query,
        },
        .Response = GetAverageModel.Response,
        .method = .GET,
        .path = "/api/user/entry/stats",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, void, Query), res: *httpz.Response) anyerror!void {
        const result = GetAverageModel.call(ctx.user_id.?, ctx.app.db, request.query) catch {
            handleResponse(res, ResponseError.not_found, null);
            return;
        };
        res.status = 200;
        try res.json(result, .{});
    }
});

pub const GetBreakdown = Endpoint(struct {
    const Query = GetBreakdownModel.Request;

    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Query = Query,
        },
        .Response = GetBreakdownModel.Response,
        .method = .GET,
        .path = "/api/user/entry/stats/detailed",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, void, Query), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const result = GetBreakdownModel.call(allocator, ctx.user_id.?, ctx.app.db, request.query) catch {
            handleResponse(res, ResponseError.not_found, null);
            return;
        };
        res.status = 200;
        try res.json(result, .{});
    }
});

pub const GetRange = Endpoint(struct {
    const Query = GetRangeModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Query = Query,
        },
        .Response = GetRangeModel.Response,
        .method = .GET,
        .path = "/api/user/entry",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, void, Query), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const result = GetRangeModel.call(allocator, ctx.user_id.?, ctx.app.db, request.query) catch {
            handleResponse(res, ResponseError.not_found, null);
            return;
        };
        defer allocator.free(result);
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
        .path = "/api/user/entry",
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

const CreateModel = @import("../models/entry_model.zig").Create;
const GetModel = @import("../models/entry_model.zig").Get;
const DeleteModel = @import("../models/entry_model.zig").Delete;
const EditModel = @import("../models/entry_model.zig").Edit;
const GetAverageModel = @import("../models/entry_model.zig").GetAverage;
const GetBreakdownModel = @import("../models/entry_model.zig").GetBreakdown;
const GetRangeModel = @import("../models/entry_model.zig").GetInRange;
const GetRecentModel = @import("../models/entry_model.zig").GetRecent;

const Handler = @import("../handler.zig");
const handleResponse = @import("../response.zig").handleResponse;
const ResponseError = @import("../response.zig").ResponseError;
const types = @import("../types.zig");

const Endpoint = @import("../endpoint.zig").Endpoint;
const EndpointRequest = @import("../endpoint.zig").EndpointRequest;
const EndpointData = @import("../endpoint.zig").EndpointData;

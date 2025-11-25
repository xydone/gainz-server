pub const endpoint_data = [_]EndpointData{
    Train.endpoint_data,
};

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Train.init(router);
}

const Train = Endpoint(struct {
    const Body = struct {
        /// datetime string (ex: 2024-01-01)
        range_start: []const u8,
        /// datetime string (ex: 2024-01-01)
        range_end: []const u8,
    };
    const Response = TrainML.Response;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = Response,
        .method = .POST,
        .path = "/api/user/analytics/weight/train",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const breakdown_request: GetBreakdownModel.Request = .{
            .range_start = request.body.range_start,
            .range_end = request.body.range_end,
        };

        const get_breakdown_response = GetBreakdownModel.call(res.arena, ctx.user_id.?, ctx.app.db, breakdown_request) catch {
            handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };

        const get_weight_request: MeasurementGetInRange.Request = .{
            .measurement_type = .weight,
            .range_start = request.body.range_start,
            .range_end = request.body.range_end,
        };

        const measurements = MeasurementGetInRange.call(ctx.user_id.?, res.arena, ctx.app.db, get_weight_request) catch {
            handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };

        var combined_values: std.ArrayList(TrainML.Data) = .empty;
        defer combined_values.deinit(res.arena);

        var measurements_by_day: std.StringHashMap(f32) = .init(res.arena);
        defer measurements_by_day.deinit();

        for (measurements) |measurement| {
            const datetime = try zdt.Datetime.fromUnix(measurement.created_at, .microsecond, null);
            var writer = std.Io.Writer.Allocating.init(res.arena);
            try datetime.toString("%d-%m-%YYYY", &writer.writer);
            try measurements_by_day.put(try writer.toOwnedSlice(), @floatCast(measurement.value));
        }

        // find matching dates
        for (get_breakdown_response) |breakdown| {
            const datetime = try zdt.Datetime.fromUnix(breakdown.created_at, .microsecond, null);
            var writer = std.Io.Writer.Allocating.init(res.arena);
            try datetime.toString("%d-%m-%YYYY", &writer.writer);
            // if there is a date, append the combined values
            if (measurements_by_day.get(try writer.toOwnedSlice())) |weight| {
                try combined_values.append(res.arena, .{
                    .weight = weight,
                    .calories = @floatCast(breakdown.nutrients.calories),
                    .protein = @floatCast(breakdown.nutrients.protein.?),
                    .sugar = @floatCast(breakdown.nutrients.sugar.?),
                    .carbs = @floatCast(breakdown.nutrients.carbs.?),
                });
            }
        }

        const result = try TrainML.run(res.arena, combined_values.items);
        res.status = 200;
        try res.json(result, .{});
    }
});

const std = @import("std");

const httpz = @import("httpz");
const zdt = @import("zdt");

const MeasurementGetInRange = @import("../../models/measurements_model.zig").GetInRange;
const GetBreakdownModel = @import("../../models/entry_model.zig").GetBreakdown;

const Handler = @import("../../handler.zig");
const ResponseError = @import("../../response.zig").ResponseError;
const handleResponse = @import("../../response.zig").handleResponse;

const types = @import("../../types.zig");

const TrainML = @import("../../ml/train.zig");

const Endpoint = @import("../../endpoint.zig").Endpoint;
const EndpointRequest = @import("../../endpoint.zig").EndpointRequest;
const EndpointData = @import("../../endpoint.zig").EndpointData;

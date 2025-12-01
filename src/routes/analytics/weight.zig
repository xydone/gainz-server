pub const endpoint_data = [_]EndpointData{
    Train.endpoint_data,
    Predict.endpoint_data,
};

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Train.init(router);
    Predict.init(router);
}

const Train = Endpoint(struct {
    const Body = struct {
        /// datetime string (ex: 2024-01-01)
        range_start: []const u8,
        /// datetime string (ex: 2024-01-01)
        range_end: []const u8,
    };
    const Response = struct {
        r2: f32,
        mae: f32,
    };
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
        const data = collectData(ctx, res.arena, request.body.range_start, request.body.range_end) catch |err| {
            switch (err) {
                error.NoFoodEntries => {
                    handleResponse(res, ResponseError.not_found, "Food entries data missing");
                    return;
                },
                error.NoMeasurements => {
                    handleResponse(res, ResponseError.not_found, "Weight data missing.");
                    return;
                },
                else => {
                    handleResponse(res, ResponseError.internal_server_error, null);
                    return;
                },
            }
        };
        defer res.arena.free(data);

        const response = TrainML.run(res.arena, ctx.app.env.DATA_DIR, ctx.user_id.?, data) catch |err| {
            return err;
        };

        const result: Response = .{ .r2 = response.r2, .mae = response.mae };
        res.status = 200;
        try res.json(result, .{});
    }
});

const Predict = Endpoint(struct {
    const Params = struct {
        /// The most recent date
        date: []const u8,
    };
    const Response = PredictML.Response;
    pub const endpoint_data: EndpointData = .{
        .Request = .{ .Params = Params },
        .Response = Response,
        .method = .GET,
        .path = "/api/user/analytics/weight/predict/:date",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const end_date = zdt.Datetime.fromString(request.params.date, "%Y-%m-%d") catch {
            //TODO: handle date parsing and verification inside handler
            handleResponse(res, ResponseError.bad_request, "Date is not valid");
            return;
        };
        const start_datetime = zdt.Datetime.sub(&end_date, zdt.Duration.fromTimespanMultiple(14, .day)) catch {
            handleResponse(res, ResponseError.bad_request, "Date is not valid");
            return;
        };
        var writer = std.Io.Writer.Allocating.init(res.arena);
        defer writer.deinit();

        start_datetime.toString("%Y-%m-%d", &writer.writer) catch {
            handleResponse(res, ResponseError.bad_request, "Date is not valid");
            return;
        };
        const start_date = try writer.toOwnedSlice();
        defer res.arena.free(start_date);

        const data = collectData(ctx, res.arena, start_date, request.params.date) catch |err| {
            switch (err) {
                error.NoFoodEntries => {
                    handleResponse(res, ResponseError.not_found, "Food entries data missing");
                    return;
                },
                error.NoMeasurements => {
                    handleResponse(res, ResponseError.not_found, "Weight data missing.");
                    return;
                },
                else => {
                    handleResponse(res, ResponseError.internal_server_error, null);
                    return;
                },
            }
        };

        // NOTE: consider opening this up to the user from the body?
        const windows: Windows = .{
            .long = 7,
            .short = 3,
        };

        const prediction = try PredictML.run(
            res.arena,
            ctx.user_id.?,
            ctx.app.env.DATA_DIR,
            data,
            windows,
        );
        try res.json(prediction, .{});
    }
});

/// Caller must free
fn collectData(
    ctx: *Handler.RequestContext,
    allocator: std.mem.Allocator,
    range_start: []const u8,
    range_end: []const u8,
) ![]Data {
    const breakdown_request: GetBreakdownModel.Request = .{
        .range_start = range_start,
        .range_end = range_end,
    };
    const get_breakdown_response = GetBreakdownModel.call(allocator, ctx.user_id.?, ctx.app.db, breakdown_request) catch return error.NoFoodEntries;
    defer allocator.free(get_breakdown_response);

    const get_weight_request: MeasurementGetInRange.Request = .{
        .measurement_type = .weight,
        .range_start = range_start,
        .range_end = range_end,
    };

    const measurements = MeasurementGetInRange.call(ctx.user_id.?, allocator, ctx.app.db, get_weight_request) catch return error.NoMeasurements;
    defer allocator.free(measurements);

    var combined_values: std.ArrayList(Data) = .empty;
    defer combined_values.deinit(allocator);

    var measurements_by_day: std.StringHashMap(f32) = .init(allocator);
    defer measurements_by_day.deinit();

    for (measurements) |measurement| {
        const datetime = try zdt.Datetime.fromUnix(measurement.created_at, .microsecond, null);
        var writer = std.Io.Writer.Allocating.init(allocator);
        try datetime.toString("%d-%m-%YYYY", &writer.writer);
        try measurements_by_day.put(try writer.toOwnedSlice(), @floatCast(measurement.value));
    }

    // find matching dates
    for (get_breakdown_response) |breakdown| {
        const datetime = try zdt.Datetime.fromUnix(breakdown.created_at, .microsecond, null);
        var writer = std.Io.Writer.Allocating.init(allocator);
        try datetime.toString("%d-%m-%YYYY", &writer.writer);
        // if there is a date, append the combined values
        if (measurements_by_day.get(try writer.toOwnedSlice())) |weight| {
            try combined_values.append(allocator, .{
                .weight = weight,
                .calories = @floatCast(breakdown.nutrients.calories),
                .protein = @floatCast(breakdown.nutrients.protein.?),
                .sugar = @floatCast(breakdown.nutrients.sugar.?),
                .carbs = @floatCast(breakdown.nutrients.carbs.?),
                .sodium = @floatCast(breakdown.nutrients.sodium.?),
            });
        }
    }

    return combined_values.toOwnedSlice(allocator);
}

const std = @import("std");

const httpz = @import("httpz");
const zdt = @import("zdt");

const MeasurementGetInRange = @import("../../models/measurements_model.zig").GetInRange;
const GetBreakdownModel = @import("../../models/entry_model.zig").GetBreakdown;

const Handler = @import("../../handler.zig");
const ResponseError = @import("../../response.zig").ResponseError;
const handleResponse = @import("../../response.zig").handleResponse;

const types = @import("../../types.zig");

const Data = @import("../../ml/weight.zig").Data;
const Features = @import("../../ml/weight.zig").Features;
const Windows = @import("../../ml/weight.zig").Windows;
const TrainML = @import("../../ml/weight.zig").Train;
const PredictML = @import("../../ml/weight.zig").Predict;

const Endpoint = @import("../../endpoint.zig").Endpoint;
const EndpointRequest = @import("../../endpoint.zig").EndpointRequest;
const EndpointData = @import("../../endpoint.zig").EndpointData;

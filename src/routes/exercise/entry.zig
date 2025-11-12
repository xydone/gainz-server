pub const endpoint_data: []EndpointData = .{
    Create.endpoint_data,
    Edit.endpoint_data,
    Delete.endpoint_data,
    GetRange.endpoint_data,
};

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    Create.init(router);
    Edit.init(router);
    Delete.init(router);
    GetRange.init(router);
}

const Create = Endpoint(struct {
    const Body = CreateModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
        },
        .Response = CreateModel.Response,
        .method = .POST,
        .path = "/api/exercise/entry/",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, void, void), res: *httpz.Response) anyerror!void {
        const response = CreateModel.call(ctx.user_id.?, ctx.app.db, request.body) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        res.status = 200;

        try res.json(response, .{});
    }
});

const Edit = Endpoint(struct {
    const Body = EditModel.Request;
    const Params = struct { entry_id: u32 };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
            .Params = Params,
        },
        .Response = EditModel.Response,
        .method = .PUT,
        .path = "/api/exercise/entry/:entry_id",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, Params, void), res: *httpz.Response) anyerror!void {
        // TODO: merge this with future handler based verification
        if (!request.body.isValid()) {
            try handleResponse(res, ResponseError.body_missing_fields, "Request body must contain at least one of the optional values");
            return;
        }
        const response = EditModel.call(ctx.user_id.?, request.params.entry_id, ctx.app.db, request.body) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
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
        .path = "/api/exercise/entry/:entry_id",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const response = DeleteModel.call(ctx.user_id.?, ctx.app.db, request.params) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        res.status = 200;

        try res.json(response, .{});
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
        .path = "/api/exercise/entry/range",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, void, Query), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const response = GetRangeModel.call(allocator, ctx.user_id.?, ctx.app.db, request.query) catch |err| {
            switch (err) {
                error.NoEntriesFound => try handleResponse(res, ResponseError.not_found, "No exercise entries found in the given range!"),
                else => try handleResponse(res, ResponseError.internal_server_error, null),
            }
            return;
        };
        defer allocator.free(response);

        res.status = 200;
        try res.json(response, .{});
    }
});
const Tests = @import("../../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Endpoint Exercise | Log Entry" {
    // SETUP
    const test_name = "Endpoint Exercise | Log Entry";
    const ht = @import("httpz").testing;
    const CreateExercise = @import("../../models/exercise/exercise.zig").Create;
    const CreateCategory = @import("../../models/exercise/category.zig").Create;
    const CreateUnit = @import("../../models/exercise/unit.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const category_request = CreateCategory.Request{ .name = "Chest" };

    const category = try CreateCategory.call(user.id, test_env.database, category_request);
    const unit = try CreateUnit.call(user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    const create_request = CreateExercise.Request{
        .name = test_name ++ " exercise",
        .unit_ids = &unit_ids,
        .category_ids = &category_ids,
    };

    const exercise = try CreateExercise.call(user.id, test_env.database, create_request);

    const body = CreateModel.Request{
        .exercise_id = @intCast(exercise.id),
        .unit_id = @intCast(unit.id),
        .value = 123,
    };
    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        try Create.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(CreateModel.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expectEqual(user.id, response.value.created_by);
        try std.testing.expectEqual(unit.id, response.value.unit_id);
        try std.testing.expectEqual(exercise.id, response.value.exercise_id);
        try std.testing.expectEqual(body.value, response.value.value);
    }
}

test "Endpoint Exercise | Edit Entry" {
    // SETUP
    const test_name = "Endpoint Exercise | Edit Entry";
    const ht = @import("httpz").testing;
    const CreateExercise = @import("../../models/exercise/exercise.zig").Create;
    const CreateUnit = @import("../../models/exercise/unit.zig").Create;
    const CreateCategory = @import("../../models/exercise/category.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const category_request = CreateCategory.Request{ .name = "Chest" };

    const category = try CreateCategory.call(user.id, test_env.database, category_request);

    const unit = try CreateUnit.call(user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    const create_request = CreateExercise.Request{
        .name = test_name ++ " exercise",
        .unit_ids = &unit_ids,
        .category_ids = &category_ids,
    };

    const exercise = try CreateExercise.call(user.id, test_env.database, create_request);

    const log_request = CreateModel.Request{
        .exercise_id = @intCast(exercise.id),
        .unit_id = @intCast(unit.id),
        .value = 123,
    };
    const log_response = try CreateModel.call(user.id, test_env.database, log_request);
    const body = EditModel.Request{
        .value = 10,
        .notes = test_name ++ "'s notes",
    };
    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    const log_id = try std.fmt.allocPrint(allocator, "{}", .{log_response.id});
    defer allocator.free(log_id);

    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        web_test.param("entry_id", log_id);

        try Edit.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(EditModel.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expectEqual(user.id, response.value.created_by);
        try std.testing.expectEqual(unit.id, response.value.unit_id);
        try std.testing.expectEqual(exercise.id, response.value.exercise_id);
        try std.testing.expectEqual(body.value, response.value.value);
        if (response.value.notes) |notes| {
            try std.testing.expectEqualStrings(body.notes.?, notes);
        }
    }
}

test "Endpoint Exercise | Delete Entry" {
    // SETUP
    const test_name = "Endpoint Exercise | Delete Entry";
    const ht = @import("httpz").testing;
    const CreateExercise = @import("../../models/exercise/exercise.zig").Create;
    const CreateCategory = @import("../../models/exercise/category.zig").Create;
    const CreateUnit = @import("../../models/exercise/unit.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const category_request = CreateCategory.Request{ .name = "Chest" };

    const category = try CreateCategory.call(user.id, test_env.database, category_request);

    const unit = try CreateUnit.call(user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    const create_request = CreateExercise.Request{
        .name = test_name ++ " exercise",
        .unit_ids = &unit_ids,
        .category_ids = &category_ids,
    };

    const exercise = try CreateExercise.call(user.id, test_env.database, create_request);

    const log_request = CreateModel.Request{
        .exercise_id = @intCast(exercise.id),
        .unit_id = @intCast(unit.id),
        .value = 123,
    };

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    const log = try CreateModel.call(user.id, test_env.database, log_request);

    const log_id = try std.fmt.allocPrint(allocator, "{}", .{log.id});
    defer allocator.free(log_id);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("entry_id", log_id);

        try Delete.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(CreateModel.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expectEqual(user.id, response.value.created_by);
        try std.testing.expectEqual(unit.id, response.value.unit_id);
        try std.testing.expectEqual(exercise.id, response.value.exercise_id);
        try std.testing.expectEqual(log_request.value, response.value.value);
    }
}

test "Endpoint Exercise | Get Range" {
    // SETUP
    const test_name = "Endpoint Exercise | Get Range";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    const CreateUnit = @import("../../models/exercise/unit.zig").Create;
    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    // create exercise category
    const CreateCategory = @import("../../models/exercise/category.zig").Create;
    const create_category_request = CreateCategory.Request{
        .name = test_name,
    };
    const create_category = try CreateCategory.call(user.id, test_env.database, create_category_request);

    const unit = try CreateUnit.call(user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });

    var unit_ids = [_]i32{unit.id};
    // create exercise
    var create_exercise_web = ht.init(.{});
    defer create_exercise_web.deinit();

    const CreateExercise = @import("../../models/exercise/exercise.zig").Create;

    var category_ids = [_]i32{create_category.id};
    const create_exercise_request = CreateExercise.Request{
        .name = test_name,
        .unit_ids = &unit_ids,
        .category_ids = &category_ids,
    };

    const create_exercise = try CreateExercise.call(user.id, test_env.database, create_exercise_request);

    // setup dates
    const zdt = @import("zdt");
    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .week));

    var lower_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.toString("%Y-%m-%d", &lower_bound_string.writer);
    try upper_bound.toString("%Y-%m-%d", &upper_bound_string.writer);

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    // log exercise
    const log_exercise = try CreateModel.call(user.id, test_env.database, .{
        .exercise_id = @intCast(create_exercise.id),
        .unit_id = @intCast(unit.id),
        .value = 123,
    });

    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.query("range_start", range_start);
        web_test.query("range_end", range_end);

        try GetRange.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]GetRangeModel.EntryList, allocator, response_body, .{});
        defer response.deinit();

        for (response.value) |entry| {
            try std.testing.expectEqual(user.id, entry.created_by);
            try std.testing.expectEqual(log_exercise.id, entry.entry_id);
            try std.testing.expectEqual(create_category.id, entry.category_id);
            try std.testing.expectEqual(log_exercise.unit_id, entry.unit_id);
            try std.testing.expectEqualStrings(create_category.name, entry.category_name);
            try std.testing.expectEqual(log_exercise.value, entry.value);
        }
    }
}

const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../../handler.zig");
const handleResponse = @import("../../response.zig").handleResponse;
const ResponseError = @import("../../response.zig").ResponseError;

const CreateModel = @import("../../models/exercise/exercise.zig").LogExercise;
const DeleteModel = @import("../../models/exercise/exercise.zig").DeleteExerciseEntry;
const EditModel = @import("../../models/exercise/exercise.zig").EditExerciseEntry;
const GetRangeModel = @import("../../models/exercise/exercise.zig").GetRange;

const jsonStringify = @import("../../util/jsonStringify.zig").jsonStringify;

const Endpoint = @import("../../handler.zig").Endpoint;
const EndpointRequest = @import("../../handler.zig").EndpointRequest;
const EndpointData = @import("../../handler.zig").EndpointData;

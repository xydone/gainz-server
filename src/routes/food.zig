const log = std.log.scoped(.food);

const endpoint_list: []Endpoint = &.{ GetFood, PostFood };

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    GetFood.init(router);
    PostFood.init(router);
    SearchFood.init(router);
    GetServing.init(router);
    CreateServing.init(router);
}

const GetFood = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = GetFoodModel.Request,
        },
        .Response = GetFoodModel.Response,
        .method = .GET,
        .config = .{},
        .path = "/api/food/:food_id",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, GetFoodModel.Request, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;

        const result = GetFoodModel.call(allocator, ctx.app.db, request.params) catch |err| {
            switch (err) {
                GetFoodModel.Errors.FoodNotFound => try handleResponse(res, ResponseError.not_found, "Food does not exist!"),
                GetFoodModel.Errors.CannotGet => try handleResponse(res, ResponseError.not_found, null),
                else => try handleResponse(res, ResponseError.internal_server_error, null),
            }
            return;
        };
        defer result.deinit(allocator);

        res.status = 200;
        try res.json(result, .{});
    }
});

const PostFood = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = CreateFood.Request,
        },
        .Response = CreateFood.Response,
        .method = .POST,
        .config = .{},
        .path = "/api/food/",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(CreateFood.Request, void, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;

        var result = CreateFood.call(ctx.user_id.?, allocator, ctx.app.db, request.body) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        defer result.deinit(allocator);

        res.status = 200;
        try res.json(result, .{});
    }
});
const SearchFood = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Query = SearchModel.Request,
        },
        .Response = SearchModel.Response,
        .method = .GET,
        .config = .{},
        .path = "/api/food/",
        .route_data = .{ .restricted = true },
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, void, SearchModel.Request), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;

        const result = SearchModel.call(allocator, ctx.app.db, request.query) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
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
const CreateServing = Endpoint(struct {
    const Body = struct { amount: f64, unit: []const u8, multiplier: f64 };
    const Params = struct { food_id: u32 };
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = Body,
            .Params = Params,
        },
        .Response = SearchModel.Response,
        .method = .POST,
        .config = .{},
        .path = "/api/food/:food_id/servings",
        .route_data = .{ .restricted = true },
    };

    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(Body, Params, void), res: *httpz.Response) anyerror!void {
        const result = CreateServingModel.call(ctx, .{
            .food_id = request.params.food_id,
            .amount = request.body.amount,
            .multiplier = request.body.multiplier,
            .unit = request.body.unit,
        }) catch {
            try handleResponse(res, ResponseError.internal_server_error, null);
            return;
        };
        res.status = 200;
        try res.json(result, .{});
    }
});

const GetServing = Endpoint(struct {
    const Params = GetServingModel.Request;
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Params = Params,
        },
        .Response = SearchModel.Response,
        .method = .GET,
        .config = .{},
        .path = "/api/food/:food_id/servings",
        .route_data = .{ .restricted = true },
    };

    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(void, Params, void), res: *httpz.Response) anyerror!void {
        const allocator = res.arena;
        const result = GetServingModel.call(allocator, ctx.app.db, request.params) catch |err| {
            switch (err) {
                GetServingModel.Errors.InvalidFoodID => try handleResponse(res, ResponseError.not_found, "Invalid food ID!"),
                else => try handleResponse(res, ResponseError.internal_server_error, null),
            }
            return;
        };
        defer allocator.free(result);
        res.status = 200;
        try res.json(result, .{});
    }
});
const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Endpoint Food | Create" {
    // SETUP
    const test_name = "Endpoint Food | Create";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const body = CreateFood.Request{
        .brand_name = "Brand " ++ test_name,
        .food_name = test_name,
        .food_grams = 100,
        .nutrients = .{
            .calories = 130,
            .fat = 10,
            .sat_fat = 2,
            .protein = 7,
            .carbs = 25,
        },
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

        try PostFood.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(CreateFood.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expect(response.value.servings != null);
        const food = response.value;
        const automatic_serving = food.servings.?[0];

        try std.testing.expectEqualStrings(body.brand_name.?, food.brand_name.?);
        try std.testing.expectEqualStrings(body.food_name.?, food.food_name.?);
        try std.testing.expectEqual(body.nutrients, food.nutrients);
        try std.testing.expectEqual(body.food_grams, automatic_serving.amount);
        try std.testing.expectEqual(body.food_grams, automatic_serving.multiplier);
    }
}
test "Endpoint Food | Get" {
    // SETUP
    const test_name = "Endpoint Food | Get";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const create_body = CreateFood.Request{
        .brand_name = "Brand " ++ test_name,
        .food_name = test_name,
        .food_grams = 100,
        .nutrients = .{
            .calories = 130,
            .fat = 10,
            .sat_fat = 2,
            .protein = 7,
            .carbs = 25,
        },
    };

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    var created_food = try CreateFood.call(user.id, allocator, test_env.database, create_body);
    defer created_food.deinit(allocator);

    const food_id_string = try std.fmt.allocPrint(allocator, "{}", .{created_food.id});
    defer allocator.free(food_id_string);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("food_id", food_id_string);

        try GetFood.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(CreateFood.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expect(response.value.servings != null);
        const food = response.value;
        const automatic_serving = food.servings.?[0];

        try std.testing.expectEqualStrings(create_body.brand_name.?, food.brand_name.?);
        try std.testing.expectEqualStrings(create_body.food_name.?, food.food_name.?);
        try std.testing.expectEqual(create_body.nutrients, food.nutrients);
        try std.testing.expectEqual(create_body.food_grams, automatic_serving.amount);
        try std.testing.expectEqual(create_body.food_grams, automatic_serving.multiplier);
    }
}

test "Endpoint Food | Get Invalid Food" {
    // SETUP
    const test_name = "Endpoint Food | Get Invalid Food";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    const food_id_string = try std.fmt.allocPrint(allocator, "{}", .{std.math.maxInt(i32)});
    defer allocator.free(food_id_string);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("food_id", food_id_string);

        try GetFood.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(404);
        const response_body = try web_test.getBody();

        const error_response = try std.json.parseFromSlice(ResponseError, allocator, response_body, .{});
        defer error_response.deinit();

        try std.testing.expectEqual(404, error_response.value.code);
        if (error_response.value.details == null) return error.ErrorDetailsNotFound;
        const details = error_response.value.details.?;
        try std.testing.expectEqualStrings("Food does not exist!", details);
    }
}

test "Endpoint Food | Search" {
    // SETUP
    const test_name = "Endpoint Food | Search";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const first_food_req = CreateFood.Request{
        .brand_name = "First Brand " ++ test_name,
        .food_name = "First " ++ test_name,
        .food_grams = 100,
        .nutrients = .{
            .calories = 130,
            .fat = 10,
            .sat_fat = 2,
            .protein = 7,
            .carbs = 25,
        },
    };

    const second_food_req = CreateFood.Request{
        .brand_name = "Second Brand " ++ test_name,
        .food_name = "Second" ++ test_name,
        .food_grams = 200,
        .nutrients = .{
            .calories = 25,
            .fat = 30,
            .sat_fat = 13,
            .protein = 4,
            .carbs = 1.9,
        },
    };

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    var first_food = try CreateFood.call(user.id, allocator, test_env.database, first_food_req);
    defer first_food.deinit(allocator);

    var second_food = try CreateFood.call(user.id, allocator, test_env.database, second_food_req);
    defer second_food.deinit(allocator);

    const body = SearchModel.Request{ .search_term = "second" };

    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.query("search_term", body.search_term);

        try SearchFood.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]SearchModel.Response, allocator, response_body, .{});
        defer response.deinit();

        for (response.value) |*food| {
            const automatic_serving = food.servings[0];

            try std.testing.expectEqualStrings(second_food_req.brand_name.?, food.brand_name.?);
            try std.testing.expectEqualStrings(second_food_req.food_name.?, food.food_name.?);
            try std.testing.expectEqual(second_food_req.nutrients, food.nutrients);
            try std.testing.expectEqual(second_food_req.food_grams, automatic_serving.amount);
            try std.testing.expectEqual(second_food_req.food_grams, automatic_serving.multiplier);
        }
    }
}

test "Endpoint Food | Create Serving" {
    // SETUP
    const test_name = "Endpoint Food | Create Serving";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const first_food_req = CreateFood.Request{
        .brand_name = "First Brand " ++ test_name,
        .food_name = "First " ++ test_name,
        .food_grams = 100,
        .nutrients = .{
            .calories = 130,
            .fat = 10,
            .sat_fat = 2,
            .protein = 7,
            .carbs = 25,
        },
    };

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    var food = try CreateFood.call(user.id, allocator, test_env.database, first_food_req);
    defer food.deinit(allocator);

    //the struct is rq.PostServings, but without food_id.
    //TODO: make this less ugly, preferably
    const ServingWithoutFoodId = struct { amount: f64, unit: []const u8, multiplier: f64 };
    const body = ServingWithoutFoodId{
        .amount = 77,
        .multiplier = 1,
        .unit = test_name,
    };

    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    const food_id_string = try std.fmt.allocPrint(allocator, "{}", .{food.id});
    defer allocator.free(food_id_string);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);
        web_test.param("food_id", food_id_string);

        try CreateServing.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(CreateServingModel.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expectEqual(food.id, response.value.food_id);
        try std.testing.expectEqual(body.amount, response.value.amount);
        try std.testing.expectEqual(body.multiplier, response.value.multiplier);
        try std.testing.expectEqualStrings(body.unit, response.value.unit);
    }
}

test "Endpoint Food | Get Serving" {
    // SETUP
    const test_name = "Endpoint Food | Get Serving";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    const first_food_req = CreateFood.Request{
        .brand_name = "First Brand " ++ test_name,
        .food_name = "First " ++ test_name,
        .food_grams = 100,
        .nutrients = .{
            .calories = 130,
            .fat = 10,
            .sat_fat = 2,
            .protein = 7,
            .carbs = 25,
        },
    };

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    var food = try CreateFood.call(user.id, allocator, test_env.database, first_food_req);
    defer food.deinit(allocator);

    //the struct is rq.PostServings, but without food_id.
    //TODO: make this less ugly, preferably
    const ServingWithoutFoodId = struct { amount: f64, unit: []const u8, multiplier: f64 };
    const create_serving_body = ServingWithoutFoodId{
        .amount = 77,
        .multiplier = 1,
        .unit = test_name,
    };
    const create_serving_string = try jsonStringify(allocator, create_serving_body);
    defer allocator.free(create_serving_string);

    const food_id_string = try std.fmt.allocPrint(allocator, "{}", .{food.id});
    defer allocator.free(food_id_string);
    var create_serving = ht.init(.{});
    defer create_serving.deinit();

    create_serving.body(create_serving_string);
    create_serving.param("food_id", food_id_string);

    try CreateServing.call(&context, create_serving.req, create_serving.res);

    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("food_id", food_id_string);

        try GetServing.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice([]GetServingModel.Response, allocator, response_body, .{});
        defer response.deinit();

        const expected_servings = [_]GetServingModel.Response{
            // Default serving
            GetServingModel.Response{
                .id = undefined, // We do not know the ID of the serving. Doing this to prevent having to make a struct
                .amount = first_food_req.food_grams,
                .multiplier = first_food_req.food_grams,
                .unit = "grams",
            },
            // Inserted serving
            GetServingModel.Response{
                .id = undefined, // We do not know the ID of the serving. Doing this to prevent having to make a struct
                .amount = create_serving_body.amount,
                .multiplier = create_serving_body.multiplier,
                .unit = create_serving_body.unit,
            },
        };

        try std.testing.expectEqual(expected_servings.len, response.value.len);
        for (expected_servings, response.value) |expected, result| {
            try std.testing.expectEqual(expected.amount, result.amount);

            try std.testing.expectEqual(expected.multiplier, result.multiplier);
            try std.testing.expectEqualStrings(expected.unit, result.unit);
        }
    }
}

test "Endpoint Food | Get Serving Invalid Food ID" {
    // SETUP
    const test_name = "Endpoint Food | Get Serving Invalid Food ID";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, test_name);
    defer user.deinit(allocator);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);

    const incorrect_food_id_string = try std.fmt.allocPrint(allocator, "{}", .{std.math.maxInt(i32)});
    defer allocator.free(incorrect_food_id_string);

    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("food_id", incorrect_food_id_string);

        try GetServing.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(404);
        const response_body = try web_test.getBody();

        const error_response = try std.json.parseFromSlice(ResponseError, allocator, response_body, .{});
        defer error_response.deinit();

        try std.testing.expectEqual(404, error_response.value.code);

        try std.testing.expectEqualStrings("Invalid food ID!", error_response.value.details.?);
    }
}

const std = @import("std");

const httpz = @import("httpz");

const GetFoodModel = @import("../models/food_model.zig").Get;
const SearchModel = @import("../models/food_model.zig").Search;
const CreateFood = @import("../models/food_model.zig").Create;
const CreateServingModel = @import("../models/servings_model.zig").Create;
const GetServingModel = @import("../models/servings_model.zig").Get;

const Handler = @import("../handler.zig");
const ResponseError = @import("../response.zig").ResponseError;
const handleResponse = @import("../response.zig").handleResponse;
const types = @import("../types.zig");
const jsonStringify = @import("../util/jsonStringify.zig").jsonStringify;

const Endpoint = @import("../handler.zig").Endpoint;
const EndpointRequest = @import("../handler.zig").EndpointRequest;
const EndpointData = @import("../handler.zig").EndpointData;

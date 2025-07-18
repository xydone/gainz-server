const std = @import("std");

const httpz = @import("httpz");

const GetFood = @import("../models/food_model.zig").Get;
const Search = @import("../models/food_model.zig").Search;
const CreateFood = @import("../models/food_model.zig").Create;
const CreateServing = @import("../models/servings_model.zig").Create;
const GetServing = @import("../models/servings_model.zig").Get;

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.food);

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    const RouteData = Handler.RouteData{ .restricted = true };

    router.*.get("/api/food/:food_id", getFood, .{ .data = &RouteData });
    router.*.get("/api/food", searchFood, .{ .data = &RouteData });
    router.*.get("/api/food/:id/servings", getServings, .{ .data = &RouteData });
    router.*.post("/api/food/:id/servings", postServings, .{ .data = &RouteData });
    router.*.post("/api/food", postFood, .{ .data = &RouteData });
}

fn getFood(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const food_id = std.fmt.parseInt(u32, req.param("food_id").?, 10) catch {
        try rs.handleResponse(res, rs.ResponseError.bad_request, "Food ID not valid integer!");
        return;
    };
    const request: GetFood.Request = .{ .food_id = food_id };

    var result = GetFood.call(ctx.app.allocator, ctx.app.db, request) catch |err| {
        switch (err) {
            GetFood.Errors.FoodNotFound => try rs.handleResponse(res, rs.ResponseError.not_found, "Food does not exist!"),
            GetFood.Errors.CannotGet => try rs.handleResponse(res, rs.ResponseError.not_found, null),
            else => try rs.handleResponse(res, rs.ResponseError.internal_server_error, null),
        }
        return;
    };
    defer result.deinit(ctx.app.allocator);

    const response = rs.GetFood{
        .brand_name = result.brand_name,
        .created_at = result.created_at,
        .food_name = result.food_name,
        .id = result.id,
        .nutrients = result.nutrients,
        .servings = result.servings.?,
    };
    res.status = 200;
    try res.json(response, .{});
}

pub fn postFood(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const json = std.json.parseFromSliceLeaky(CreateFood.Request, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };

    var result = CreateFood.call(ctx.user_id.?, ctx.app.allocator, ctx.app.db, json) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    defer result.deinit(ctx.app.allocator);

    res.status = 200;
    try res.json(result, .{});
}

pub fn searchFood(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const query = try req.query();
    var search_term: []const u8 = undefined;
    if (query.get("search")) |q| {
        search_term = q;
    } else {
        try rs.handleResponse(res, rs.ResponseError.bad_request, null);
        return;
    }
    const request: Search.Request = .{ .search_term = search_term };
    const result = Search.call(ctx.app.allocator, ctx.app.db, request) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    defer ctx.app.allocator.free(result);
    res.status = 200;

    var response = std.ArrayList(rs.SearchFood).init(ctx.app.allocator);
    defer response.deinit();
    for (result) |food| {
        try response.append(rs.SearchFood{
            .brand_name = food.brand_name,
            .food_name = food.food_name,
            .created_at = food.created_at,
            .id = food.id,
            .nutrients = food.nutrients,
            .servings = food.servings.?,
        });
    }
    defer for (result) |*food| food.deinit(ctx.app.allocator);
    try res.json(response.items, .{});
}

pub fn postServings(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const food_id = try std.fmt.parseInt(i32, req.param("id").?, 10);
    if (food_id < 0) {
        try rs.handleResponse(res, rs.ResponseError.body_missing, "Food ID cannot be negative");
        return;
    }
    //the struct is rq.PostServings, but without food_id.
    //TODO: make this less ugly, preferably
    const ServingWithoutFoodId = struct { amount: f64, unit: []const u8, multiplier: f64 };
    const request: ServingWithoutFoodId = std.json.parseFromSliceLeaky(ServingWithoutFoodId, ctx.app.allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.body_missing_fields, null);
        return;
    };
    const result = CreateServing.call(ctx, .{
        .food_id = food_id,
        .amount = request.amount,
        .multiplier = request.multiplier,
        .unit = request.unit,
    }) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    defer result.deinit(ctx.app.allocator);
    res.status = 200;
    try res.json(result, .{});
}

pub fn getServings(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const request = GetServing.Request{ .food_id = try std.fmt.parseInt(i32, req.param("id").?, 10) };
    const result = GetServing.call(ctx, request) catch |err| {
        switch (err) {
            GetServing.Errors.InvalidFoodID => try rs.handleResponse(res, rs.ResponseError.not_found, "Invalid food ID!"),
            else => try rs.handleResponse(res, rs.ResponseError.internal_server_error, null),
        }
        return;
    };
    defer ctx.app.allocator.free(result);
    res.status = 200;
    try res.json(result, .{});
}

const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Endpoint Food | Create" {
    // SETUP
    const test_name = "Endpoint Food | Create";
    const ht = @import("httpz").testing;
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
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
    const body_string = try std.json.stringifyAlloc(allocator, body, .{});
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(user.id, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        postFood(&context, web_test.req, web_test.res) catch |err| {
            benchmark.fail(err);
            return err;
        };
        web_test.expectStatus(200) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response_body = web_test.getBody() catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response = std.json.parseFromSlice(CreateFood.Response, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        std.testing.expect(response.value.servings != null) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const food = response.value;
        const automatic_serving = food.servings.?[0];

        std.testing.expectEqualStrings(body.brand_name.?, food.brand_name.?) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(body.food_name.?, food.food_name.?) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(body.nutrients, food.nutrients) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(body.food_grams, automatic_serving.amount) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(body.food_grams, automatic_serving.multiplier) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}
test "Endpoint Food | Get" {
    // SETUP
    const test_name = "Endpoint Food | Get";
    const ht = @import("httpz").testing;
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
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
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("food_id", food_id_string);

        getFood(&context, web_test.req, web_test.res) catch |err| {
            benchmark.fail(err);
            return err;
        };
        web_test.expectStatus(200) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response_body = web_test.getBody() catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response = std.json.parseFromSlice(CreateFood.Response, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        std.testing.expect(response.value.servings != null) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const food = response.value;
        const automatic_serving = food.servings.?[0];

        std.testing.expectEqualStrings(create_body.brand_name.?, food.brand_name.?) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(create_body.food_name.?, food.food_name.?) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_body.nutrients, food.nutrients) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_body.food_grams, automatic_serving.amount) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_body.food_grams, automatic_serving.multiplier) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "Endpoint Food | Get Invalid Food" {
    // SETUP
    const test_name = "Endpoint Food | Get Invalid Food";
    const ht = @import("httpz").testing;
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
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
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("food_id", food_id_string);

        getFood(&context, web_test.req, web_test.res) catch |err| {
            benchmark.fail(err);
            return err;
        };
        web_test.expectStatus(404) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response_body = web_test.getBody() catch |err| {
            benchmark.fail(err);
            return err;
        };

        const error_response = std.json.parseFromSlice(rs.ResponseError, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer error_response.deinit();

        std.testing.expectEqual(404, error_response.value.code) catch |err| {
            benchmark.fail(err);
            return err;
        };
        if (error_response.value.details == null) return error.ErrorDetailsNotFound;
        const details = error_response.value.details.?;
        std.testing.expectEqualStrings("Food does not exist!", details) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "Endpoint Food | Search" {
    // SETUP
    const test_name = "Endpoint Food | Search";
    const ht = @import("httpz").testing;
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
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

    const body = Search.Request{ .search_term = "second" };

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.query("search", body.search_term);

        searchFood(&context, web_test.req, web_test.res) catch |err| {
            benchmark.fail(err);
            return err;
        };
        web_test.expectStatus(200) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response_body = web_test.getBody() catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response = std.json.parseFromSlice(Search.Response, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        for (response.value) |*food| {
            std.testing.expect(food.servings != null) catch |err| {
                benchmark.fail(err);
                return err;
            };
            const automatic_serving = food.servings.?[0];

            std.testing.expectEqualStrings(second_food_req.brand_name.?, food.brand_name.?) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqualStrings(second_food_req.food_name.?, food.food_name.?) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(second_food_req.nutrients, food.nutrients) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(second_food_req.food_grams, automatic_serving.amount) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(second_food_req.food_grams, automatic_serving.multiplier) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

test "Endpoint Food | Create Serving" {
    // SETUP
    const test_name = "Endpoint Food | Create Serving";
    const ht = @import("httpz").testing;
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
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
    const body_string = try std.json.stringifyAlloc(allocator, body, .{});
    defer allocator.free(body_string);

    const food_id_string = try std.fmt.allocPrint(allocator, "{}", .{food.id});
    defer allocator.free(food_id_string);
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);
        web_test.param("id", food_id_string);

        postServings(&context, web_test.req, web_test.res) catch |err| {
            benchmark.fail(err);
            return err;
        };
        web_test.expectStatus(200) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response_body = web_test.getBody() catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response = std.json.parseFromSlice(CreateServing.Response, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        std.testing.expectEqual(food.id, response.value.food_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(body.amount, response.value.amount) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(body.multiplier, response.value.multiplier) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(body.unit, response.value.unit) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "Endpoint Food | Get Serving" {
    // SETUP
    const test_name = "Endpoint Food | Get Serving";
    const ht = @import("httpz").testing;
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
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
    const create_serving_string = try std.json.stringifyAlloc(allocator, create_serving_body, .{});
    defer allocator.free(create_serving_string);

    const food_id_string = try std.fmt.allocPrint(allocator, "{}", .{food.id});
    defer allocator.free(food_id_string);
    var create_serving = ht.init(.{});
    defer create_serving.deinit();

    create_serving.body(create_serving_string);
    create_serving.param("id", food_id_string);

    try postServings(&context, create_serving.req, create_serving.res);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("id", food_id_string);

        getServings(&context, web_test.req, web_test.res) catch |err| {
            benchmark.fail(err);
            return err;
        };
        web_test.expectStatus(200) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response_body = web_test.getBody() catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response = std.json.parseFromSlice([]GetServing.Response, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        const expected_servings = [_]GetServing.Response{
            // Default serving
            GetServing.Response{
                .id = undefined, // We do not know the ID of the serving. Doing this to prevent having to make a struct
                .amount = first_food_req.food_grams,
                .multiplier = first_food_req.food_grams,
                .unit = "grams",
            },
            // Inserted serving
            GetServing.Response{
                .id = undefined, // We do not know the ID of the serving. Doing this to prevent having to make a struct
                .amount = create_serving_body.amount,
                .multiplier = create_serving_body.multiplier,
                .unit = create_serving_body.unit,
            },
        };

        std.testing.expectEqual(expected_servings.len, response.value.len) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (expected_servings, response.value) |expected, result| {
            std.testing.expectEqual(expected.amount, result.amount) catch |err| {
                benchmark.fail(err);
                return err;
            };

            std.testing.expectEqual(expected.multiplier, result.multiplier) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqualStrings(expected.unit, result.unit) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

test "Endpoint Food | Get Serving Invalid Food ID" {
    // SETUP
    const test_name = "Endpoint Food | Get Serving Invalid Food ID";
    const ht = @import("httpz").testing;
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
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
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.param("id", incorrect_food_id_string);

        getServings(&context, web_test.req, web_test.res) catch |err| {
            benchmark.fail(err);
            return err;
        };
        web_test.expectStatus(404) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response_body = web_test.getBody() catch |err| {
            benchmark.fail(err);
            return err;
        };

        const error_response = std.json.parseFromSlice(rs.ResponseError, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer error_response.deinit();

        std.testing.expectEqual(404, error_response.value.code) catch |err| {
            benchmark.fail(err);
            return err;
        };

        std.testing.expectEqualStrings("Invalid food ID!", error_response.value.details.?) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

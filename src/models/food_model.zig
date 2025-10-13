const std = @import("std");

const pg = @import("pg");
const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;

const Handler = @import("../handler.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.food_model);

/// Have to call .deinit() to free memory after usage
pub const FoodList = struct {
    list: []Food,

    pub fn deinit(self: FoodList, allocator: std.mem.Allocator) void {
        for (self.list) |*food| {
            food.deinit(allocator);
        }

        allocator.free(self.list);
    }
};

pub const Food = struct {
    id: i32,
    created_at: i64,
    food_name: ?[]const u8,
    brand_name: ?[]const u8,
    nutrients: types.Nutrients,
    servings: ?[]types.Servings = null,

    pub fn format(
        self: Food,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt; // autofix
        _ = options; // autofix

        try writer.writeAll("Food{ ");
        try writer.print(".created_at = {d}, .food_name = \"{?s}\", .brand_name = \"{?s}\", .nutrients = {any}, .servings = {?any}", .{
            self.created_at,
            self.food_name,
            self.brand_name,
            self.nutrients,
            self.servings,
        });
        try writer.writeAll(" }");
    }

    pub fn deinit(self: *Food, allocator: std.mem.Allocator) void {
        if (self.brand_name) |name| allocator.free(name);
        if (self.food_name) |name| allocator.free(name);
        if (self.servings) |servings| {
            defer allocator.free(servings);
            for (servings) |serving| {
                allocator.free(serving.unit);
            }
        }
    }
};

pub const Get = struct {
    pub const Request = struct {
        food_id: u32,
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        food_name: ?[]const u8,
        brand_name: ?[]const u8,
        nutrients: types.Nutrients,
        servings: []types.Servings,

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            if (self.brand_name) |name| allocator.free(name);
            if (self.food_name) |name| allocator.free(name);
            for (self.servings) |serving| {
                allocator.free(serving.unit);
            }
            allocator.free(self.servings);
        }
    };
    pub const Errors = error{
        CannotGet,
        FoodNotFound,
        ServingsParsingError,
        OutOfMemory,
    } || DatabaseErrors;
    /// Have to call .deinit() to free memory after usage
    pub fn call(allocator: std.mem.Allocator, database: *Pool, request: Get.Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var row = conn.rowOpts(query_string, //
            .{request.food_id}, .{ .column_names = true }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);

            return error.CannotGet;
        } orelse return error.FoodNotFound;
        defer row.deinit() catch {};

        const id = row.get(i32, 0);
        const created_at = row.getCol(i64, "created_at");
        const food_name = row.getCol([]u8, "food_name");
        const brand_name = row.getCol([]u8, "brand_name");
        const nutrients = types.Nutrients{
            .calories = row.getCol(f64, "calories"),
            .fat = row.getCol(?f64, "fat"),
            .sat_fat = row.getCol(?f64, "sat_fat"),
            .polyunsat_fat = row.getCol(?f64, "polyunsat_fat"),
            .monounsat_fat = row.getCol(?f64, "monounsat_fat"),
            .trans_fat = row.getCol(?f64, "trans_fat"),
            .cholesterol = row.getCol(?f64, "cholesterol"),
            .sodium = row.getCol(?f64, "sodium"),
            .potassium = row.getCol(?f64, "potassium"),
            .carbs = row.getCol(?f64, "carbs"),
            .fiber = row.getCol(?f64, "fiber"),
            .sugar = row.getCol(?f64, "sugar"),
            .protein = row.getCol(?f64, "protein"),
            .vitamin_a = row.getCol(?f64, "vitamin_a"),
            .vitamin_c = row.getCol(?f64, "vitamin_c"),
            .calcium = row.getCol(?f64, "calcium"),
            .iron = row.getCol(?f64, "iron"),
        };
        const servings_unparsed = row.getCol([]u8, "servings");
        const servings = std.json.parseFromSliceLeaky([]types.Servings, allocator, servings_unparsed, .{}) catch |err| {
            log.err("Error parsing servings JSON within search query. Error: {}", .{err});
            return error.ServingsParsingError;
        };

        return Response{
            .id = id,
            .created_at = created_at,
            .food_name = allocator.dupe(u8, food_name) catch return error.OutOfMemory,
            .brand_name = allocator.dupe(u8, brand_name) catch return error.OutOfMemory,
            .nutrients = nutrients,
            .servings = servings,
        };
    }
    const query_string =
        \\SELECT
        \\f.*,
        \\JSON_AGG(
        \\CASE
        \\WHEN s.created_at IS NULL THEN NULL
        \\ELSE json_build_object(
        \\'id',
        \\s.id,
        \\'amount',
        \\s.amount,
        \\'unit',
        \\s.unit,
        \\'multiplier',
        \\s.multiplier
        \\)
        \\END
        \\) AS servings
        \\FROM
        \\food AS f
        \\LEFT JOIN servings s ON f.id = s.food_id
        \\WHERE
        \\f.id = $1
        \\GROUP BY f.id;
    ;
};

pub const Search = struct {
    pub const Request = struct {
        search_term: []const u8,
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        food_name: ?[]const u8,
        brand_name: ?[]const u8,
        nutrients: types.Nutrients,
        servings: []types.Servings,

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            if (self.brand_name) |name| allocator.free(name);
            if (self.food_name) |name| allocator.free(name);
            for (self.servings) |serving| {
                allocator.free(serving.unit);
            }
            allocator.free(self.servings);
        }
    };
    pub const Errors = error{
        CannotSearch,
        ServingsParsingError,
        OutOfMemory,
    } || DatabaseErrors;
    /// Caller must free slice
    pub fn call(allocator: std.mem.Allocator, database: *Pool, request: Request) Errors![]Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var result = conn.queryOpts(query_string, //
            .{request.search_term}, .{ .column_names = true, .allocator = allocator }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotSearch;
        };
        defer result.deinit();
        var response: std.ArrayList(Response) = .empty;
        while (result.next() catch return error.CannotSearch) |row| {
            const id = row.get(i32, 0);
            const created_at = row.getCol(i64, "created_at");
            const food_name = row.getCol([]u8, "food_name");
            const brand_name = row.getCol([]u8, "brand_name");
            const nutrients = types.Nutrients{
                .calories = row.getCol(f64, "calories"),
                .fat = row.getCol(?f64, "fat"),
                .sat_fat = row.getCol(?f64, "sat_fat"),
                .polyunsat_fat = row.getCol(?f64, "polyunsat_fat"),
                .monounsat_fat = row.getCol(?f64, "monounsat_fat"),
                .trans_fat = row.getCol(?f64, "trans_fat"),
                .cholesterol = row.getCol(?f64, "cholesterol"),
                .sodium = row.getCol(?f64, "sodium"),
                .potassium = row.getCol(?f64, "potassium"),
                .carbs = row.getCol(?f64, "carbs"),
                .fiber = row.getCol(?f64, "fiber"),
                .sugar = row.getCol(?f64, "sugar"),
                .protein = row.getCol(?f64, "protein"),
                .vitamin_a = row.getCol(?f64, "vitamin_a"),
                .vitamin_c = row.getCol(?f64, "vitamin_c"),
                .calcium = row.getCol(?f64, "calcium"),
                .iron = row.getCol(?f64, "iron"),
                .added_sugars = row.getCol(?f64, "added_sugars"),
                .vitamin_d = row.getCol(?f64, "vitamin_d"),
                .sugar_alcohols = row.getCol(?f64, "sugar_alcohols"),
            };
            const servings_unparsed = row.getCol([]u8, "servings");
            const servings = std.json.parseFromSliceLeaky([]types.Servings, allocator, servings_unparsed, .{}) catch |err| {
                log.err("Error parsing servings JSON within search query. Error: {}", .{err});
                return error.ServingsParsingError;
            };

            response.append(allocator, Response{
                .id = id,
                .created_at = created_at,
                .food_name = allocator.dupe(u8, food_name) catch return error.OutOfMemory,
                .brand_name = allocator.dupe(u8, brand_name) catch return error.OutOfMemory,
                .nutrients = nutrients,
                .servings = servings,
            }) catch return error.OutOfMemory;
        }
        return response.toOwnedSlice(allocator) catch return error.OutOfMemory;
    }

    const query_string =
        \\SELECT
        \\  f.*,
        \\  JSON_AGG(
        \\    CASE
        \\      WHEN s.created_at IS NULL THEN NULL
        \\      ELSE json_build_object(
        \\        'id',
        \\        s.id,
        \\        'amount',
        \\        s.amount,
        \\        'unit',
        \\        s.unit,
        \\        'multiplier',
        \\        s.multiplier
        \\      )
        \\    END
        \\  ) AS servings
        \\FROM
        \\  food f
        \\  LEFT JOIN servings s ON f.id = s.food_id
        \\WHERE
        \\  f.food_name ILIKE '%' || $1 || '%'
        \\  OR f.brand_name ILIKE '%' || $1 || '%'
        \\GROUP BY
        \\  f.id
    ;
};

pub const Create = struct {
    pub const Request = struct {
        brand_name: ?[]const u8,
        food_name: ?[]const u8,
        food_grams: f64,
        nutrients: types.Nutrients,
    };
    pub const Response = Food;
    pub const Errors = error{
        CannotCreate,
        OutOfMemory,
    } || DatabaseErrors;
    /// Have to call .deinit() to free memory after usage
    pub fn call(user_id: i32, allocator: std.mem.Allocator, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var row = conn.rowOpts(query_string, //
            .{ user_id, request.brand_name, request.food_name, request.food_grams, request.nutrients.calories, request.nutrients.fat, request.nutrients.sat_fat, request.nutrients.polyunsat_fat, request.nutrients.monounsat_fat, request.nutrients.trans_fat, request.nutrients.cholesterol, request.nutrients.sodium, request.nutrients.potassium, request.nutrients.carbs, request.nutrients.fiber, request.nutrients.sugar, request.nutrients.protein, request.nutrients.vitamin_a, request.nutrients.vitamin_c, request.nutrients.calcium, request.nutrients.iron } //
            , .{ .column_names = true, .allocator = allocator }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer row.deinit() catch {};

        const id = row.getCol(i32, "id");
        const created_at = row.getCol(i64, "created_at");
        const food_name = row.getCol([]u8, "food_name");
        const brand_name = row.getCol([]u8, "brand_name");
        const nutrients = types.Nutrients{
            .calories = row.getCol(f64, "calories"),
            .fat = row.getCol(?f64, "fat"),
            .sat_fat = row.getCol(?f64, "sat_fat"),
            .polyunsat_fat = row.getCol(?f64, "polyunsat_fat"),
            .monounsat_fat = row.getCol(?f64, "monounsat_fat"),
            .trans_fat = row.getCol(?f64, "trans_fat"),
            .cholesterol = row.getCol(?f64, "cholesterol"),
            .sodium = row.getCol(?f64, "sodium"),
            .potassium = row.getCol(?f64, "potassium"),
            .carbs = row.getCol(?f64, "carbs"),
            .fiber = row.getCol(?f64, "fiber"),
            .sugar = row.getCol(?f64, "sugar"),
            .protein = row.getCol(?f64, "protein"),
            .vitamin_a = row.getCol(?f64, "vitamin_a"),
            .vitamin_c = row.getCol(?f64, "vitamin_c"),
            .calcium = row.getCol(?f64, "calcium"),
            .iron = row.getCol(?f64, "iron"),
        };

        const servings = allocator.alloc(types.Servings, 1) catch return error.OutOfMemory;
        servings[0] = types.Servings{
            .amount = row.getCol(f64, "serving_amount"),
            .id = row.getCol(i32, "serving_id"),
            .multiplier = row.getCol(f64, "serving_multiplier"),
            .unit = allocator.dupe(u8, row.getCol([]u8, "serving_unit")) catch return error.OutOfMemory,
        };

        return Response{
            .id = id,
            .created_at = created_at,
            .food_name = allocator.dupe(u8, food_name) catch return error.OutOfMemory,
            .brand_name = allocator.dupe(u8, brand_name) catch return error.OutOfMemory,
            .nutrients = nutrients,
            .servings = servings,
        };
    }

    const query_string =
        \\WITH inserted_food AS (
        \\ insert into
        \\  food (
        \\    created_by,
        \\    brand_name,
        \\    food_name,
        \\    food_grams,
        \\    calories,
        \\    fat,
        \\    sat_fat,
        \\    polyunsat_fat,
        \\    monounsat_fat,
        \\    trans_fat,
        \\    cholesterol,
        \\    sodium,
        \\    potassium,
        \\    carbs,
        \\    fiber,
        \\    sugar,
        \\    protein,
        \\    vitamin_a,
        \\    vitamin_c,
        \\    calcium,
        \\    iron
        \\  )
        \\values
        \\($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21)
        \\RETURNING * 
        \\),
        \\inserted_serving AS (
        \\INSERT INTO servings (created_by, food_id, amount, unit, multiplier) 
        \\SELECT created_by, id, $4, 'grams', $4 FROM inserted_food
        \\RETURNING *
        \\)
        \\SELECT
        \\ifs.*,  
        \\iss.id AS serving_id,
        \\iss.amount AS serving_amount,
        \\iss.unit AS serving_unit,
        \\iss.multiplier AS serving_multiplier,
        \\iss.created_at AS serving_created_at
        \\FROM
        \\inserted_food ifs
        \\LEFT JOIN
        \\inserted_serving iss ON ifs.id = iss.food_id;
    ;
};

pub const Delete = struct {
    pub const Request = struct {
        id: u32,
    };
    pub const Response = Food;
    pub const Errors = error{
        CannotDelete,
        OutOfMemory,
    } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!bool {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        const amount_deleted = conn.exec(query_string, //
            .{ user_id, request.id } //
        ) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotDelete;
        } orelse return error.CannotDelete;
        return amount_deleted == 1;
    }

    const query_string = "DELETE FROM food WHERE created_by = $1 AND id = $2";
};

const Tests = @import("../tests/tests.zig");

const TestSetup = Tests.TestSetup;

test "API Food | Create" {
    // SETUP
    const test_name = "API Food | Create";
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;

    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    const create_request = Create.Request{
        .food_name = test_name,
        .brand_name = "Brand " ++ test_name,
        .food_grams = 100,
        .nutrients = types.Nutrients{ .calories = 350 },
    };
    // TEST
    {
        var food = try Create.call(setup.user.id, allocator, test_env.database, create_request);
        defer food.deinit(allocator);

        try std.testing.expectEqualStrings(create_request.brand_name.?, food.brand_name.?);
        try std.testing.expectEqualStrings(create_request.food_name.?, food.food_name.?);
        try std.testing.expectEqual(create_request.food_grams, food.servings.?[0].amount);
        try std.testing.expectEqual(create_request.food_grams, food.servings.?[0].multiplier);
        try std.testing.expectEqual(create_request.nutrients, food.nutrients);
    }
}

test "API Food | Get" {
    const test_env = Tests.test_env;
    // SETUP
    const allocator = std.testing.allocator;
    const test_name = "API Food | Get";

    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    //insert food
    const create_request = Create.Request{
        .food_name = test_name,
        .brand_name = "Brand " ++ test_name,
        .food_grams = 100,
        .nutrients = types.Nutrients{ .calories = 350 },
    };
    var food = try Create.call(setup.user.id, allocator, test_env.database, create_request);
    defer food.deinit(allocator);

    const get_request = Get.Request{
        .food_id = @intCast(food.id),
    };
    // TEST
    {
        var response = try Get.call(allocator, test_env.database, get_request);
        defer response.deinit(allocator);

        try std.testing.expectEqual(food.id, response.id);
        try std.testing.expectEqualStrings(food.food_name.?, response.food_name.?);
        try std.testing.expectEqualStrings(food.brand_name.?, response.brand_name.?);

        try std.testing.expectEqual(food.created_at, response.created_at);
        for (food.servings.?, response.servings) |inserted_serving, response_serving| {
            try std.testing.expectEqual(inserted_serving.amount, response_serving.amount);
            try std.testing.expectEqual(inserted_serving.id, response_serving.id);
            try std.testing.expectEqual(inserted_serving.multiplier, response_serving.multiplier);
            try std.testing.expectEqualStrings(inserted_serving.unit, response_serving.unit);
        }
    }
}

test "API Food | Search" {
    const test_env = Tests.test_env;
    // SETUP
    const allocator = std.testing.allocator;
    const test_name = "API Food | Search";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    //insert food
    const create_request = Create.Request{
        .food_name = test_name,
        .brand_name = "Brand " ++ test_name,
        .food_grams = 100,
        .nutrients = types.Nutrients{ .calories = 350 },
    };
    var inserted_food = try Create.call(setup.user.id, allocator, test_env.database, create_request);
    defer inserted_food.deinit(allocator);

    // TEST
    {
        const search_food = Search.Request{
            .search_term = test_name[0..15],
        };

        const results = try Search.call(allocator, test_env.database, search_food);
        defer {
            for (results) |*food| {
                food.deinit(allocator);
            }
            allocator.free(results);
        }

        if (results.len == 0) return error.FoodNotFoundViaSearch;

        const result = results[0];
        try std.testing.expectEqual(inserted_food.id, result.id);
        try std.testing.expectEqualStrings(inserted_food.food_name.?, result.food_name.?);
        try std.testing.expectEqualStrings(inserted_food.brand_name.?, result.brand_name.?);
        try std.testing.expectEqual(inserted_food.created_at, result.created_at);
        try std.testing.expectEqual(inserted_food.servings.?[0].amount, result.servings[0].amount);
        try std.testing.expectEqual(inserted_food.servings.?[0].id, result.servings[0].id);
        try std.testing.expectEqual(inserted_food.servings.?[0].multiplier, result.servings[0].multiplier);
        try std.testing.expectEqualStrings(inserted_food.servings.?[0].unit, result.servings[0].unit);
    }
}

// TODO: test for delete

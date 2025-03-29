const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.food_model);

/// Have to call .deinit() to free memory after usage
pub const FoodList = struct {
    list: []Food,
    allocator: std.mem.Allocator,

    pub fn deinit(self: FoodList) void {
        for (0..self.list.len) |i| {
            self.list[i].deinit();
        }
        self.allocator.free(self.list);
    }
};

pub const Food = struct {
    allocator: std.mem.Allocator,
    id: i32,
    created_at: i64,
    food_name: ?[]u8,
    brand_name: ?[]u8,
    nutrients: types.Nutrients,
    servings: ?std.json.Parsed([]types.Servings) = null,

    pub fn format(
        self: Food,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt; // autofix
        _ = options; // autofix

        try writer.writeAll("Food{ ");
        try writer.print(".created_at = {d}, .food_name = \"{?s}\", .brand_name = \"{?s}\", .nutrients = {any}, .servings = {?}", .{
            self.created_at,
            self.food_name,
            self.brand_name,
            self.nutrients,
            self.servings,
        });
        try writer.writeAll(" }");
    }

    pub fn deinit(self: *Food) void {
        if (self.servings) |servings| {
            servings.deinit();
        }
    }

    /// Have to call .deinit() to free memory after usage
    pub fn get(allocator: std.mem.Allocator, database: *pg.Pool, request: rq.GetFood) anyerror!Food {
        var conn = try database.acquire();
        defer conn.release();
        var row = conn.rowOpts(SQL_STRINGS.get, //
            .{request.food_id}, .{ .column_names = true }) catch |err| {
            if (conn.err) |pg_err| {
                log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
            }
            return err;
        } orelse return error.NotFound;
        defer row.deinit() catch {};

        const id = row.get(i32, 0);
        const created_at = row.get(i64, 1);
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
        const servings = std.json.parseFromSlice([]types.Servings, allocator, servings_unparsed, .{}) catch |err| {
            log.err("Error parsing servings JSON within search query. Error: {}", .{err});
            return err;
        };
        return Food{
            .allocator = allocator,
            .id = id,
            .created_at = created_at,
            .food_name = food_name,
            .brand_name = brand_name,
            .nutrients = nutrients,
            .servings = servings,
        };
    }

    /// Have to call .deinit() to free memory after usage
    pub fn search(allocator: std.mem.Allocator, database: *pg.Pool, request: rq.SearchFood) anyerror!FoodList {
        var conn = try database.acquire();
        defer conn.release();
        var result = conn.queryOpts(SQL_STRINGS.search, //
            .{request.search_term}, .{ .column_names = true, .allocator = allocator }) catch |err| {
            if (conn.err) |pg_err| {
                log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
            }
            return err;
        };
        defer result.deinit();
        var response = std.ArrayList(Food).init(allocator);
        while (try result.next()) |row| {
            const id = row.get(i32, 0);
            const created_at = row.get(i64, 1);

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
            const servings = std.json.parseFromSlice([]types.Servings, allocator, servings_unparsed, .{}) catch |err| {
                log.err("Error parsing servings JSON within search query. Error: {}", .{err});
                return err;
            };

            try response.append(Food{
                .allocator = allocator,
                .id = id,
                .created_at = created_at,
                .food_name = food_name,
                .brand_name = brand_name,
                .nutrients = nutrients,
                .servings = servings,
            });
        }
        return FoodList{ .list = try response.toOwnedSlice(), .allocator = allocator };
    }

    /// Returns the ID of the new food
    pub fn create(user_id: i32, database: *pg.Pool, request: rq.PostFood) anyerror!i32 {
        var conn = try database.acquire();
        defer conn.release();

        var row = try conn.row(SQL_STRINGS.create, //
            .{ user_id, request.brand_name, request.food_name, request.food_grams, request.nutrients.calories, request.nutrients.fat, request.nutrients.sat_fat, request.nutrients.polyunsat_fat, request.nutrients.monounsat_fat, request.nutrients.trans_fat, request.nutrients.cholesterol, request.nutrients.sodium, request.nutrients.potassium, request.nutrients.carbs, request.nutrients.fiber, request.nutrients.sugar, request.nutrients.protein, request.nutrients.vitamin_a, request.nutrients.vitamin_c, request.nutrients.calcium, request.nutrients.iron } //
        ) orelse return error.FoodNotFound;
        defer row.deinit() catch {};
        return row.get(i32, 0);
    }
};

const SQL_STRINGS = struct {
    pub const get =
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
    pub const search =
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
    pub const create =
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
        \\returning id, brand_name, food_name, created_by
        \\)
        \\INSERT INTO servings (created_by, food_id, amount, unit, multiplier) 
        \\SELECT created_by, id, $4, 'grams', $4 FROM inserted_food
        \\RETURNING food_id;
    ;
};

const Tests = @import("../tests/tests.zig");

test "create food" {
    var test_env = Tests.test_env;

    const brand = try std.fmt.allocPrint(test_env.allocator, "Test brand", .{});
    defer test_env.allocator.free(brand);
    const food_name = try std.fmt.allocPrint(test_env.allocator, "Test food name", .{});
    defer test_env.allocator.free(food_name);

    const create_request = rq.PostFood{
        .brand_name = brand,
        .food_name = food_name,
        .food_grams = 100,
        .nutrients = types.Nutrients{ .calories = 350 },
    };
    const food_id = try Food.create(1, test_env.database, create_request);
    try std.testing.expectEqual(1, food_id);
}

test "get food" {
    const test_env = Tests.test_env;

    const get_request = rq.GetFood{ .food_id = 1 };
    var response = try Food.get(test_env.allocator, test_env.database, get_request);
    defer response.deinit();

    try std.testing.expectEqual(1, response.id);
    try std.testing.expectEqualStrings("Test food name", response.food_name.?);
    try std.testing.expectEqualStrings("Test brand", response.brand_name.?);
}

test "search" {
    const test_env = Tests.test_env;

    const search_food = rq.SearchFood{ .search_term = "Te" };

    var results = try Food.search(test_env.allocator, test_env.database, search_food);
    defer results.deinit();

    if (results.list.len == 0) return error.FoodNotFoundViaSearch;

    for (results.list) |food| {
        const serving = food.servings orelse return error.MissingInitialServing;
        const initial_serving = serving.value[0];
        try std.testing.expectEqualStrings("Test food name", food.food_name.?);
        try std.testing.expectEqualStrings("Test brand", food.brand_name.?);
        try std.testing.expectEqual(350, food.nutrients.calories);
        try std.testing.expectEqual(null, food.nutrients.added_sugars);
        try std.testing.expectEqual(100, initial_serving.amount);
        try std.testing.expectEqual(100, initial_serving.multiplier);
        try std.testing.expectEqualStrings("grams", initial_serving.unit);
    }
}

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
        for (self.list) |*food| {
            food.deinit();
        }

        self.allocator.free(self.list);
    }
};

pub const Food = struct {
    allocator: std.mem.Allocator,
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

    pub fn deinit(self: *Food) void {
        if (self.brand_name) |name| self.allocator.free(name);
        if (self.food_name) |name| self.allocator.free(name);
        if (self.servings) |servings| {
            defer self.allocator.free(servings);
            for (servings) |serving| {
                self.allocator.free(serving.unit);
            }
        }
    }
};
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
        return err;
    };

    return Food{
        .allocator = allocator,
        .id = id,
        .created_at = created_at,
        .food_name = try allocator.dupe(u8, food_name),
        .brand_name = try allocator.dupe(u8, brand_name),
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
            return err;
        };

        try response.append(Food{
            .allocator = allocator,
            .id = id,
            .created_at = created_at,
            .food_name = try allocator.dupe(u8, food_name),
            .brand_name = try allocator.dupe(u8, brand_name),
            .nutrients = nutrients,
            .servings = servings,
        });
    }
    return FoodList{ .list = try response.toOwnedSlice(), .allocator = allocator };
}

pub fn create(user_id: i32, allocator: std.mem.Allocator, database: *pg.Pool, request: rq.PostFood) anyerror!Food {
    var conn = try database.acquire();
    defer conn.release();

    var row = try conn.rowOpts(SQL_STRINGS.create, //
        .{ user_id, request.brand_name, request.food_name, request.food_grams, request.nutrients.calories, request.nutrients.fat, request.nutrients.sat_fat, request.nutrients.polyunsat_fat, request.nutrients.monounsat_fat, request.nutrients.trans_fat, request.nutrients.cholesterol, request.nutrients.sodium, request.nutrients.potassium, request.nutrients.carbs, request.nutrients.fiber, request.nutrients.sugar, request.nutrients.protein, request.nutrients.vitamin_a, request.nutrients.vitamin_c, request.nutrients.calcium, request.nutrients.iron } //
        , .{ .column_names = true, .allocator = allocator }) orelse return error.FoodNotFound;
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

    const servings = try allocator.alloc(types.Servings, 1);
    servings[0] = types.Servings{
        .amount = row.getCol(f64, "serving_amount"),
        .id = row.getCol(i32, "serving_id"),
        .multiplier = row.getCol(f64, "serving_multiplier"),
        .unit = try allocator.dupe(u8, row.getCol([]u8, "serving_unit")),
    };

    return Food{
        .allocator = allocator,
        .id = id,
        .created_at = created_at,
        .food_name = try allocator.dupe(u8, food_name),
        .brand_name = try allocator.dupe(u8, brand_name),
        .nutrients = nutrients,
        .servings = servings,
    };
}

pub fn delete(user_id: i32, database: *pg.Pool, request: rq.DeleteFood) !bool {
    var conn = try database.acquire();
    defer conn.release();

    const amount_deleted = try conn.exec(SQL_STRINGS.delete, //
        .{ user_id, request.id } //
    ) orelse return error.FoodNotFound;
    return amount_deleted == 1;
}

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

    pub const delete = "DELETE FROM food WHERE created_by = $1 AND id = $2";
};

const Tests = @import("../tests/tests.zig");

const TestSetup = Tests.TestSetup;

test "API Food | Create" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const test_name = "API Food | Create";
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;

    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    const create_request = rq.PostFood{
        .food_name = test_name,
        .brand_name = "Brand " ++ test_name,
        .food_grams = 100,
        .nutrients = types.Nutrients{ .calories = 350 },
    };
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        var food = create(setup.user.id, allocator, test_env.database, create_request) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer food.deinit();

        std.testing.expectEqualStrings(create_request.brand_name.?, food.brand_name.?) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(create_request.food_name.?, food.food_name.?) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_request.food_grams, food.servings.?[0].amount) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_request.food_grams, food.servings.?[0].multiplier) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_request.nutrients, food.nutrients) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "API Food | Get" {
    const test_env = Tests.test_env;
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;
    const test_name = "API Food | Get";

    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    //insert food
    const create_request = rq.PostFood{
        .food_name = test_name,
        .brand_name = "Brand " ++ test_name,
        .food_grams = 100,
        .nutrients = types.Nutrients{ .calories = 350 },
    };
    var food = try create(setup.user.id, allocator, test_env.database, create_request);
    defer food.deinit();

    const get_request = rq.GetFood{
        .food_id = @intCast(food.id),
    };
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        var response = get(allocator, test_env.database, get_request) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        std.testing.expectEqual(food.id, response.id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(food.food_name.?, response.food_name.?) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(food.brand_name.?, response.brand_name.?) catch |err| {
            benchmark.fail(err);
            return err;
        };

        std.testing.expectEqual(food.created_at, response.created_at) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (food.servings.?, response.servings.?) |inserted_serving, response_serving| {
            std.testing.expectEqual(inserted_serving.amount, response_serving.amount) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted_serving.id, response_serving.id) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted_serving.multiplier, response_serving.multiplier) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqualStrings(inserted_serving.unit, response_serving.unit) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

test "API Food | Search" {
    const test_env = Tests.test_env;
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;
    const test_name = "API Food | Search";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    //insert food
    const create_request = rq.PostFood{
        .food_name = test_name,
        .brand_name = "Brand " ++ test_name,
        .food_grams = 100,
        .nutrients = types.Nutrients{ .calories = 350 },
    };
    var inserted_food = try create(setup.user.id, allocator, test_env.database, create_request);
    defer inserted_food.deinit();

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const search_food = rq.SearchFood{
            .search_term = test_name[0..15],
        };

        var results = search(allocator, test_env.database, search_food) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer results.deinit();

        if (results.list.len == 0) return error.FoodNotFoundViaSearch;

        const result = results.list[0];
        std.testing.expectEqual(inserted_food.id, result.id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(inserted_food.food_name.?, result.food_name.?) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(inserted_food.brand_name.?, result.brand_name.?) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(inserted_food.created_at, result.created_at) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(inserted_food.servings.?[0].amount, result.servings.?[0].amount) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(inserted_food.servings.?[0].id, result.servings.?[0].id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(inserted_food.servings.?[0].multiplier, result.servings.?[0].multiplier) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(inserted_food.servings.?[0].unit, result.servings.?[0].unit) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

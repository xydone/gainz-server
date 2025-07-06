const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");
const log = std.log.scoped(.entry_model);
const Food = @import("food_model.zig").Food;

const EntryBreakdownList = struct {
    created_at: i64,
    nutrients: types.Nutrients,
};

pub const EntryBreakdown = struct {
    list: []EntryBreakdownList,

    pub fn deinit(self: *EntryBreakdown, allocator: std.mem.Allocator) void {
        allocator.free(self.list);
    }
};

pub const EntryList = struct {
    list: []Entry,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *EntryList) void {
        for (self.list) |entry| {
            if (entry.food) |food| {
                if (food.brand_name) |buf| self.allocator.free(buf);
                if (food.food_name) |buf| self.allocator.free(buf);
            }
        }
        self.allocator.free(self.list);
    }
};

pub const Entry = struct {
    id: i32,
    user_id: i32,
    food_id: i32,
    serving_id: i32,
    created_at: i64,
    category: types.MealCategory,
    amount: f64,
    food: ?Food = null,

    pub fn format(
        self: Entry,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt; // autofix
        _ = options; // autofix

        try writer.writeAll("Entry{ ");
        try writer.print(".id = {d}, .user_id = {d}, .food_id = {d}, serving_id = {d}, .created_at = {d}, category = {any}, amount = {d}, food = {?}", .{
            self.id,
            self.user_id,
            self.food_id,
            self.serving_id,
            self.created_at,
            self.category,
            self.amount,
            self.food,
        });
        try writer.writeAll(" }");
    }
};
pub fn create(user_id: i32, database: *pg.Pool, request: rq.PostEntry) anyerror!Entry {
    var conn = try database.acquire();
    defer conn.release();

    var row = conn.row(SQL_STRINGS.create, //
        .{ request.category, request.food_id, user_id, request.amount, request.serving_id, request.created_at }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.EntryNotCreated;
    //NOTE: you must deinitialize rows or else query time balloons 10x
    defer row.deinit() catch {};
    const id = row.get(i32, 0);
    const u_id = row.get(i32, 1);
    const f_id = row.get(i32, 2);
    const s_id = row.get(i32, 3);
    const created_at = row.get(i64, 4);
    const category = row.get(types.MealCategory, 5);
    const amount = row.get(f64, 6);

    return Entry{
        .id = id,
        .user_id = u_id,
        .food_id = f_id,
        .serving_id = s_id,
        .category = category,
        .created_at = created_at,
        .amount = amount,
    };
}

pub fn delete(database: *pg.Pool, request: rq.DeleteEntry) anyerror!void {
    var conn = try database.acquire();
    defer conn.release();
    const deleted = try conn.exec(SQL_STRINGS.delete, .{request.id}) orelse return error.NotFound;
    if (deleted == 0) return error.NotFound;
}

pub fn edit(ctx: *Handler.RequestContext, request: rq.EditEntry, entry_id: u32) anyerror!void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    const deleted = try conn.exec(SQL_STRINGS.edit, .{ entry_id, request.meal_category, request.amount, request.serving_id }) orelse return error.NotFound;
    if (deleted == 0) return error.NotFound;
}

pub fn get(user_id: i32, database: *pg.Pool, request: rq.GetEntry) anyerror!Entry {
    var conn = try database.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.get, //
        .{ user_id, request.entry }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;
    defer row.deinit() catch {};

    const id = row.get(i32, 0);
    const created_at = row.get(i64, 1);
    const food_id = row.get(i32, 3);
    const meal_category = row.get(types.MealCategory, 4);
    const amount = row.get(f64, 5);
    const serving_id = row.get(i32, 6);
    return Entry{
        .created_at = created_at,
        .id = id,
        .user_id = user_id,
        .food_id = food_id,
        .category = meal_category,
        .amount = amount,
        .serving_id = serving_id,
    };
}

pub fn getRecent(allocator: std.mem.Allocator, user_id: i32, database: *pg.Pool, request: rq.GetEntryRecent) anyerror!EntryList {
    var conn = try database.acquire();
    defer conn.release();
    var result = conn.queryOpts(SQL_STRINGS.getRecent, .{ user_id, request.limit }, .{ .column_names = true, .allocator = allocator }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };

    defer result.deinit();
    var response = std.ArrayList(Entry).init(allocator);
    while (try result.next()) |row| {
        const entry_id = row.getCol(i32, "entry_id");
        const serving_id = row.getCol(i32, "serving_id");
        const food_id = row.getCol(i32, "id");
        const entry_created_at = row.getCol(i64, "entry_created_at");
        const food_created_at = row.getCol(i64, "created_at");
        const amount = row.getCol(f64, "amount");
        const food_name = try std.fmt.allocPrint(allocator, "{?s}", .{row.getCol(?[]u8, "food_name")});
        const brand_name = try std.fmt.allocPrint(allocator, "{?s}", .{row.getCol(?[]u8, "brand_name")});
        const nutrients = try row.to(types.Nutrients, .{ .map = .name });
        try response.append(Entry{
            .id = entry_id,
            .user_id = user_id,
            .food_id = food_id,
            .serving_id = serving_id,
            .created_at = entry_created_at,
            .amount = amount,
            .category = types.MealCategory.breakfast,
            .food = Food{
                .brand_name = brand_name,
                .food_name = food_name,
                .created_at = food_created_at,
                .id = food_id,
                .nutrients = nutrients,
            },
        });
    }
    if (response.items.len == 0) return error.EntriesNotFound;
    return EntryList{ .list = try response.toOwnedSlice(), .allocator = allocator };
}

pub fn getInRange(allocator: std.mem.Allocator, user_id: i32, database: *pg.Pool, request: rq.GetEntryRange) anyerror!EntryList {
    var conn = try database.acquire();
    defer conn.release();
    var result = conn.queryOpts(SQL_STRINGS.getInRange, .{ user_id, request.range_start, request.range_end }, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(Entry).init(allocator);

    while (try result.next()) |row| {
        const entry_id = row.getCol(i32, "id");
        const food_id = row.getCol(i32, "food_id");
        const serving_id = row.getCol(i32, "serving_id");
        const entry_created_at = row.getCol(i64, "entry_created_at");
        const food_created_at = row.getCol(i64, "food_created_at");
        const category = row.getCol(types.MealCategory, "category");
        const food_name = row.getCol(?[]u8, "food_name");
        const brand_name = row.getCol(?[]u8, "brand_name");
        const amount = row.getCol(f64, "amount");
        const food_name_duped = if (food_name != null) try allocator.dupe(u8, food_name.?) else null;
        const brand_name_duped = if (brand_name != null) try allocator.dupe(u8, brand_name.?) else null;
        const nutrients = try row.to(types.Nutrients, .{ .map = .name });

        const entry = Entry{
            .id = entry_id,
            .food_id = food_id,
            .user_id = user_id,
            .serving_id = serving_id,
            .created_at = entry_created_at,
            .category = category,
            .amount = amount,
            .food = Food{
                .id = food_id,
                .brand_name = brand_name_duped,
                .food_name = food_name_duped,
                .nutrients = nutrients,
                .created_at = food_created_at,
            },
        };

        try response.append(entry);
    }
    if (response.items.len == 0) return error.NotFound;
    return EntryList{ .list = try response.toOwnedSlice(), .allocator = allocator };
}

pub fn getAverage(user_id: i32, database: *pg.Pool, request: rq.GetEntryBreakdown) anyerror!types.Nutrients {
    var conn = try database.acquire();
    defer conn.release();
    var row = conn.rowOpts(SQL_STRINGS.getAverage, //
        .{ user_id, request.range_start, request.range_end }, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;
    defer row.deinit() catch {};
    // whenever the range is invalid, it returns one row of nulls, this is a check and a fix for that
    const calories = row.getCol(?f64, "calories") orelse return error.NotFound;
    const nutrients = types.Nutrients{
        .calories = calories,
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
    return nutrients;
}

/// Caller must deinit
pub fn getBreakdown(allocator: std.mem.Allocator, user_id: i32, database: *pg.Pool, request: rq.GetEntryBreakdown) anyerror!EntryBreakdown {
    var conn = try database.acquire();
    defer conn.release();
    var result = conn.queryOpts(SQL_STRINGS.getStatsDetailed, //
        .{ user_id, request.range_start, request.range_end }, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    var response = std.ArrayList(EntryBreakdownList).init(allocator);
    while (try result.next()) |row| {
        const entry_date = row.getCol(i64, "entry_date");
        const nutrients = try row.to(types.Nutrients, .{ .map = .name });
        try response.append(.{ .created_at = entry_date, .nutrients = nutrients });
    }
    if (response.items.len == 0) return error.NotFound;
    return .{ .list = try response.toOwnedSlice() };
}

const SQL_STRINGS = struct {
    pub const get = "SELECT * FROM entry WHERE user_id = $1 and id = $2;";
    pub const delete = "DELETE FROM entry WHERE id = $1";
    pub const edit = "UPDATE entry SET category = $2, amount = $3, serving_id = $4 WHERE id = $1;";
    pub const getRecent =
        \\SELECT
        \\e.id AS entry_id,
        \\e.serving_id AS serving_id,
        \\e.created_at AS entry_created_at,
        \\e.amount AS amount,
        \\f.*
        \\FROM
        \\entry AS e
        \\JOIN food AS f on e.food_id = f.id
        \\WHERE
        \\user_id = $1
        \\ORDER BY
        \\e.created_at DESC
        \\LIMIT
        \\$2;
    ;
    pub const create =
        \\INSERT INTO
        \\entry (category, food_id, user_id, amount, serving_id, created_at)
        \\VALUES
        \\($1, $2, $3, $4, $5, COALESCE($6, NOW()))
        \\RETURNING
        \\id,
        \\user_id,
        \\food_id,
        \\serving_id,
        \\created_at,
        \\category,
        \\amount;
    ;
    pub const getInRange =
        \\SELECT e.id AS id,
        \\  f.id AS food_id,
        \\  s.id AS serving_id,
        \\  e.created_at AS entry_created_at,
        \\  f.created_at AS food_created_at,
        \\  f.brand_name as brand_name,
        \\  f.food_name as food_name,
        \\  e.amount AS amount,
        \\  e.category AS category,
        \\  (
        \\    e.amount * s.multiplier * f.calories / f.food_grams
        \\  ) AS calories,
        \\  (e.amount * s.multiplier * f.fat / f.food_grams) AS fat,
        \\  (
        \\    e.amount * s.multiplier * f.sat_fat / f.food_grams
        \\  ) AS sat_fat,
        \\  (
        \\    e.amount * s.multiplier * f.polyunsat_fat / f.food_grams
        \\  ) AS polyunsat_fat,
        \\  (
        \\    e.amount * s.multiplier * f.monounsat_fat / f.food_grams
        \\  ) AS monounsat_fat,
        \\  (
        \\    e.amount * s.multiplier * f.trans_fat / f.food_grams
        \\  ) AS trans_fat,
        \\  (
        \\    e.amount * s.multiplier * f.cholesterol / f.food_grams
        \\  ) AS cholesterol,
        \\  (
        \\    e.amount * s.multiplier * f.sodium / f.food_grams
        \\  ) AS sodium,
        \\  (
        \\    e.amount * s.multiplier * f.potassium / f.food_grams
        \\  ) AS potassium,
        \\  (e.amount * s.multiplier * f.carbs / f.food_grams) AS carbs,
        \\  (e.amount * s.multiplier * f.fiber / f.food_grams) AS fiber,
        \\  (e.amount * s.multiplier * f.sugar / f.food_grams) AS sugar,
        \\  (
        \\    e.amount * s.multiplier * f.protein / f.food_grams
        \\  ) AS protein,
        \\  (
        \\    e.amount * s.multiplier * f.vitamin_a / f.food_grams
        \\  ) AS vitamin_a,
        \\  (
        \\    e.amount * s.multiplier * f.vitamin_c / f.food_grams
        \\  ) AS vitamin_c,
        \\  (
        \\    e.amount * s.multiplier * f.calcium / f.food_grams
        \\  ) AS calcium,
        \\  (e.amount * s.multiplier * f.iron / f.food_grams) AS iron,
        \\  (
        \\    e.amount * s.multiplier * f.added_sugars / f.food_grams
        \\  ) AS added_sugars,
        \\  (
        \\    e.amount * s.multiplier * f.vitamin_d / f.food_grams
        \\  ) AS vitamin_d,
        \\  (
        \\    e.amount * s.multiplier * f.sugar_alcohols / f.food_grams
        \\  ) AS sugar_alcohols
        \\FROM entry e
        \\  JOIN servings s ON e.serving_id = s.id
        \\  JOIN food f ON e.food_id = f.id
        \\WHERE e.user_id = $1
        \\  AND DATE (e.created_at) >= $2
        \\  AND DATE (e.created_at) <= $3
        \\ORDER BY e.created_at DESC,
        \\  e.category;
    ;
    pub const getAverage = "SELECT AVG(daily_calories) AS calories, AVG(daily_fat) AS fat, AVG(daily_sat_fat) AS sat_fat, AVG(daily_polyunsat_fat) AS polyunsat_fat, AVG(daily_monounsat_fat) AS monounsat_fat, AVG(daily_trans_fat) AS trans_fat, AVG(daily_cholesterol) AS cholesterol, AVG(daily_sodium) AS sodium, AVG(daily_potassium) AS potassium, AVG(daily_carbs) AS carbs, AVG(daily_fiber) AS fiber, AVG(daily_sugar) AS sugar, AVG(daily_protein) AS protein, AVG(daily_vitamin_a) AS vitamin_a, AVG(daily_vitamin_c) AS vitamin_c, AVG(daily_calcium) AS calcium, AVG(daily_iron) AS iron, AVG(daily_added_sugars) AS added_sugars, AVG(daily_vitamin_d) AS vitamin_d, AVG(daily_sugar_alcohols) AS sugar_alcohols FROM ( SELECT DATE(e.created_at) AS entry_date, SUM(e.amount * s.multiplier * f.calories / f.food_grams) AS daily_calories, SUM(e.amount * s.multiplier * f.fat / f.food_grams) AS daily_fat, SUM(e.amount * s.multiplier * f.sat_fat / f.food_grams) AS daily_sat_fat, SUM(e.amount * s.multiplier * f.polyunsat_fat / f.food_grams) AS daily_polyunsat_fat, SUM(e.amount * s.multiplier * f.monounsat_fat / f.food_grams) AS daily_monounsat_fat, SUM(e.amount * s.multiplier * f.trans_fat / f.food_grams) AS daily_trans_fat, SUM(e.amount * s.multiplier * f.cholesterol / f.food_grams) AS daily_cholesterol, SUM(e.amount * s.multiplier * f.sodium / f.food_grams) AS daily_sodium, SUM(e.amount * s.multiplier * f.potassium / f.food_grams) AS daily_potassium, SUM(e.amount * s.multiplier * f.carbs / f.food_grams) AS daily_carbs, SUM(e.amount * s.multiplier * f.fiber / f.food_grams) AS daily_fiber, SUM(e.amount * s.multiplier * f.sugar / f.food_grams) AS daily_sugar, SUM(e.amount * s.multiplier * f.protein / f.food_grams) AS daily_protein, SUM(e.amount * s.multiplier * f.vitamin_a / f.food_grams) AS daily_vitamin_a, SUM(e.amount * s.multiplier * f.vitamin_c / f.food_grams) AS daily_vitamin_c, SUM(e.amount * s.multiplier * f.calcium / f.food_grams) AS daily_calcium, SUM(e.amount * s.multiplier * f.iron / f.food_grams) AS daily_iron, SUM(e.amount * s.multiplier * f.added_sugars / f.food_grams) AS daily_added_sugars, SUM(e.amount * s.multiplier * f.vitamin_d / f.food_grams) AS daily_vitamin_d, SUM(e.amount * s.multiplier * f.sugar_alcohols / f.food_grams) AS daily_sugar_alcohols FROM entry e JOIN servings s ON e.serving_id = s.id JOIN food f ON e.food_id = f.id WHERE e.user_id = $1 AND Date(e.created_at) >= $2 AND Date(e.created_at) <= $3 GROUP BY entry_date ) AS daily_data";
    pub const getStatsDetailed =
        \\ SELECT
        \\ entry_date::timestamp,
        \\ AVG(daily_calories) AS calories,
        \\ AVG(daily_fat) AS fat,
        \\ AVG(daily_sat_fat) AS sat_fat,
        \\ AVG(daily_polyunsat_fat) AS polyunsat_fat,
        \\ AVG(daily_monounsat_fat) AS monounsat_fat,
        \\ AVG(daily_trans_fat) AS trans_fat,
        \\ AVG(daily_cholesterol) AS cholesterol,
        \\ AVG(daily_sodium) AS sodium,
        \\ AVG(daily_potassium) AS potassium,
        \\ AVG(daily_carbs) AS carbs,
        \\ AVG(daily_fiber) AS fiber,
        \\ AVG(daily_sugar) AS sugar,
        \\ AVG(daily_protein) AS protein,
        \\ AVG(daily_vitamin_a) AS vitamin_a,
        \\ AVG(daily_vitamin_c) AS vitamin_c,
        \\ AVG(daily_calcium) AS calcium,
        \\ AVG(daily_iron) AS iron,
        \\ AVG(daily_added_sugars) AS added_sugars,
        \\ AVG(daily_vitamin_d) AS vitamin_d,
        \\ AVG(daily_sugar_alcohols) AS sugar_alcohols
        \\ FROM
        \\ (
        \\ SELECT
        \\ DATE (e.created_at) AS entry_date,
        \\ SUM(
        \\ e.amount * s.multiplier * f.calories / f.food_grams
        \\ ) AS daily_calories,
        \\ SUM(e.amount * s.multiplier * f.fat / f.food_grams) AS daily_fat,
        \\ SUM(
        \\ e.amount * s.multiplier * f.sat_fat / f.food_grams
        \\ ) AS daily_sat_fat,
        \\ SUM(
        \\ e.amount * s.multiplier * f.polyunsat_fat / f.food_grams
        \\ ) AS daily_polyunsat_fat,
        \\ SUM(
        \\ e.amount * s.multiplier * f.monounsat_fat / f.food_grams
        \\ ) AS daily_monounsat_fat,
        \\ SUM(
        \\ e.amount * s.multiplier * f.trans_fat / f.food_grams
        \\ ) AS daily_trans_fat,
        \\ SUM(
        \\ e.amount * s.multiplier * f.cholesterol / f.food_grams
        \\ ) AS daily_cholesterol,
        \\ SUM(e.amount * s.multiplier * f.sodium / f.food_grams) AS daily_sodium,
        \\ SUM(
        \\ e.amount * s.multiplier * f.potassium / f.food_grams
        \\ ) AS daily_potassium,
        \\ SUM(e.amount * s.multiplier * f.carbs / f.food_grams) AS daily_carbs,
        \\ SUM(e.amount * s.multiplier * f.fiber / f.food_grams) AS daily_fiber,
        \\ SUM(e.amount * s.multiplier * f.sugar / f.food_grams) AS daily_sugar,
        \\ SUM(
        \\ e.amount * s.multiplier * f.protein / f.food_grams
        \\ ) AS daily_protein,
        \\ SUM(
        \\ e.amount * s.multiplier * f.vitamin_a / f.food_grams
        \\ ) AS daily_vitamin_a,
        \\ SUM(
        \\ e.amount * s.multiplier * f.vitamin_c / f.food_grams
        \\ ) AS daily_vitamin_c,
        \\ SUM(
        \\ e.amount * s.multiplier * f.calcium / f.food_grams
        \\ ) AS daily_calcium,
        \\ SUM(e.amount * s.multiplier * f.iron / f.food_grams) AS daily_iron,
        \\ SUM(
        \\ e.amount * s.multiplier * f.added_sugars / f.food_grams
        \\ ) AS daily_added_sugars,
        \\ SUM(
        \\ e.amount * s.multiplier * f.vitamin_d / f.food_grams
        \\ ) AS daily_vitamin_d,
        \\ SUM(
        \\ e.amount * s.multiplier * f.sugar_alcohols / f.food_grams
        \\ ) AS daily_sugar_alcohols
        \\ FROM
        \\ entry e
        \\ JOIN servings s ON e.serving_id = s.id
        \\ JOIN food f ON e.food_id = f.id
        \\ WHERE
        \\ e.user_id = $1
        \\ AND Date(e.created_at) >= $2
        \\ AND Date(e.created_at) <= $3
        \\ GROUP BY
        \\ entry_date
        \\ ) AS daily_data 
        \\ GROUP BY
        \\ entry_date
        \\ ORDER BY
        \\ entry_date
    ;
};

//TESTS

const Tests = @import("../tests/tests.zig");
const BaseTestSetup = Tests.TestSetup;

const TestSetup = struct {
    user: User,
    food: Food,

    const User = @import("users_model.zig").Create.Response;
    pub fn init(database: *pg.Pool, unique_name: []const u8) !TestSetup {
        const Create = @import("food_model.zig").Create;
        const allocator = std.testing.allocator;

        // User insert
        const user = try createUser(database, unique_name);

        const create_food = Create.Request{
            .brand_name = unique_name,
            .food_name = "Test food name",
            .food_grams = 100,
            .nutrients = types.Nutrients{ .calories = 350 },
        };

        return TestSetup{ .user = user, .food = try Create.call(user.id, allocator, database, create_food) };
    }

    pub fn createUser(database: *pg.Pool, name: []const u8) !User {
        return BaseTestSetup.createUser(database, name);
    }

    pub fn deinit(self: *TestSetup) void {
        self.user.deinit();
    }
};

test "API Entry | Create" {
    //SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const Create = @import("food_model.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, "API Entry | Create");
    defer user.deinit(allocator);

    const brand = try std.fmt.allocPrint(allocator, "Test brand", .{});
    defer allocator.free(brand);
    const food_name = try std.fmt.allocPrint(allocator, "Test food name", .{});
    defer allocator.free(food_name);

    const create_food = Create.Request{
        .brand_name = brand,
        .food_name = food_name,
        .food_grams = 100,
        .nutrients = types.Nutrients{ .calories = 350 },
    };
    var food = try Create.call(user.id, allocator, test_env.database, create_food);
    defer food.deinit(allocator);

    const create_entry = rq.PostEntry{
        .food_id = food.id,
        .category = .breakfast,
        .serving_id = food.servings.?[0].id,
        .amount = 0.5,
    };
    var entry_id: i32 = undefined;
    // TEST
    {
        var benchmark = Benchmark.start("API Entry | Create");
        defer benchmark.end();

        const entry = create(user.id, test_env.database, create_entry) catch |err| {
            benchmark.fail(err);
            return err;
        };
        entry_id = entry.id;

        std.testing.expectEqual(create_entry.food_id, entry.food_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_entry.serving_id, entry.serving_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_entry.amount, entry.amount) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_entry.category, entry.category) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "API Entry | Get" {
    //SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    var setup = TestSetup.init(test_env.database, "API Entry | Get") catch return error.TestSetupFailed;
    defer {
        setup.food.deinit(allocator);
        setup.user.deinit(allocator);
    }

    const create_entry = rq.PostEntry{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry = try create(setup.user.id, test_env.database, create_entry);
    const get_request = rq.GetEntry{ .entry = @intCast(entry.id) };
    // TEST
    {
        var benchmark = Benchmark.start("API Entry | Get");
        defer benchmark.end();

        const result = get(setup.user.id, test_env.database, get_request) catch |err| {
            benchmark.fail(err);
            return err;
        };

        std.testing.expectEqual(entry.food_id, result.food_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(entry.serving_id, result.serving_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(entry.user_id, result.user_id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(entry.category, result.category) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(entry.amount, result.amount) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expect(result.food == null) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "API Entry | Get range" {
    //SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const zdt = @import("zdt");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    var setup = TestSetup.init(test_env.database, "API Entry | Get range") catch return error.TestSetupFailed;
    defer {
        setup.food.deinit(allocator);
        setup.user.deinit(allocator);
    }

    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    var date = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var date_string = std.ArrayList(u8).init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", date_string.writer());
    // Create multiple entries
    var create_entry = rq.PostEntry{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry_1 = try create(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    const entry_2 = try create(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    _ = try create(setup.user.id, test_env.database, create_entry);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .day));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .day));

    var lower_bound_string = std.ArrayList(u8).init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string = std.ArrayList(u8).init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.format("%Y-%m-%d", .{}, lower_bound_string.writer());
    try upper_bound.format("%Y-%m-%d", .{}, upper_bound_string.writer());

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    const get_request = rq.GetEntryRange{
        .range_start = range_start,
        .range_end = range_end,
    };
    // TEST
    {
        var benchmark = Benchmark.start("API Entry | Get range");
        defer benchmark.end();

        var entry_list = getInRange(allocator, setup.user.id, test_env.database, get_request) catch |err| {
            benchmark.fail(err);
            return err;
        };

        defer entry_list.deinit();

        std.testing.expectEqual(2, entry_list.list.len) catch |err| {
            benchmark.fail(err);
            return err;
        };

        // The most recently inserted entry in the range will appear first. Entry 3 is outside of the range
        const inserted_entries = [_]Entry{ entry_2, entry_1 };

        for (entry_list.list, inserted_entries) |entry, inserted| {
            std.testing.expectEqual(inserted.id, entry.id) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted.amount, entry.amount) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(setup.food.id, entry.food.?.id) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqualStrings(setup.food.brand_name.?, entry.food.?.brand_name.?) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqualStrings(setup.food.food_name.?, entry.food.?.food_name.?) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}
test "API Entry | Get range (empty)" {
    //SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const zdt = @import("zdt");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    var setup = TestSetup.init(test_env.database, "API Entry | Get range (empty)") catch return error.TestSetupFailed;
    defer {
        setup.food.deinit(allocator);
        setup.user.deinit(allocator);
    }

    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    // Create Entries
    var date = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var date_string = std.ArrayList(u8).init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", date_string.writer());
    // Create multiple entries
    var create_entry = rq.PostEntry{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    _ = try create(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    _ = try create(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    _ = try create(setup.user.id, test_env.database, create_entry);

    var lower_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(3, .day));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(3, .day));

    var lower_bound_string = std.ArrayList(u8).init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string = std.ArrayList(u8).init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.format("%Y-%m-%d", .{}, lower_bound_string.writer());
    try upper_bound.format("%Y-%m-%d", .{}, upper_bound_string.writer());

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    const get_request = rq.GetEntryRange{
        .range_start = range_start,
        .range_end = range_end,
    };
    // TEST
    {
        var benchmark = Benchmark.start("API Entry | Get range (empty)");
        defer benchmark.end();

        if (getInRange(allocator, setup.user.id, test_env.database, get_request)) |*entry_list| {
            const list = @constCast(entry_list);
            list.deinit();
        } else |err| {
            std.testing.expectEqual(error.NotFound, err) catch |inner_err| benchmark.fail(inner_err);
        }
    }
}

test "API Entry | Get recent (all)" {
    //SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const zdt = @import("zdt");
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    var setup = TestSetup.init(test_env.database, "API Entry | Get recent (all)") catch return error.TestSetupFailed;
    defer {
        setup.food.deinit(allocator);
        setup.user.deinit(allocator);
    }

    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    // Create Entries
    var date = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var date_string = std.ArrayList(u8).init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", date_string.writer());
    var create_entry = rq.PostEntry{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry_1 = try create(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    const entry_2 = try create(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    const entry_3 = try create(setup.user.id, test_env.database, create_entry);

    const get_entry_recent = rq.GetEntryRecent{
        .limit = 50,
    };
    // TEST
    {
        var benchmark = Benchmark.start("API Entry | Get recent (all)");
        defer benchmark.end();

        var entry_list = getRecent(allocator, setup.user.id, test_env.database, get_entry_recent) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer entry_list.deinit();

        // The entries are sorted by the created_at date
        // Meaning, the id or insert order wouldn't match the return
        const ordered_entries = [_]Entry{ entry_2, entry_1, entry_3 };
        std.testing.expectEqual(3, entry_list.list.len) catch |err| {
            benchmark.fail(err);
            return err;
        };

        for (entry_list.list, ordered_entries) |entry, ordered| {
            std.testing.expectEqual(ordered.id, entry.id) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(ordered.amount, entry.amount) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(ordered.category, entry.category) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(ordered.serving_id, entry.serving_id) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqualStrings(setup.food.food_name.?, entry.food.?.food_name.?) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqualStrings(setup.food.brand_name.?, entry.food.?.brand_name.?) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

test "API Entry | Get recent (partial)" {
    //SETUP
    const zdt = @import("zdt");
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    var setup = TestSetup.init(test_env.database, "API Entry | Get recent (partial)") catch return error.TestSetupFailed;
    defer {
        setup.food.deinit(allocator);
        setup.user.deinit(allocator);
    }

    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    // Create Entries
    var date = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var date_string = std.ArrayList(u8).init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", date_string.writer());
    var create_entry = rq.PostEntry{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry_1 = try create(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    const entry_2 = try create(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    _ = try create(setup.user.id, test_env.database, create_entry);

    const get_entry_recent = rq.GetEntryRecent{
        .limit = 2,
    };
    const inserted_entries = [_]Entry{ entry_2, entry_1 };
    // TEST
    {
        var benchmark = Benchmark.start("API Entry | Get recent (partial)");
        defer benchmark.end();

        var entry_list = getRecent(allocator, setup.user.id, test_env.database, get_entry_recent) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer entry_list.deinit();

        std.testing.expectEqual(inserted_entries.len, entry_list.list.len) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (entry_list.list, inserted_entries) |entry, inserted| {
            std.testing.expectEqual(inserted.id, entry.id) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted.amount, entry.amount) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted.category, entry.category) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted.serving_id, entry.serving_id) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqualStrings(setup.food.food_name.?, entry.food.?.food_name.?) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqualStrings(setup.food.brand_name.?, entry.food.?.brand_name.?) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

test "API Entry | Get recent (empty)" {
    //SETUP
    const zdt = @import("zdt");
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    var setup = TestSetup.init(test_env.database, "API Entry | Get recent (empty)") catch return error.TestSetupFailed;
    defer {
        setup.food.deinit(allocator);
        setup.user.deinit(allocator);
    }

    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    // Create Entries
    var date = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var date_string = std.ArrayList(u8).init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", date_string.writer());
    var create_entry = rq.PostEntry{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    _ = try create(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    _ = try create(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    _ = try create(setup.user.id, test_env.database, create_entry);
    const get_entry_recent = rq.GetEntryRecent{
        .limit = 0,
    };
    // TEST
    {
        var benchmark = Benchmark.start("API Entry | Get recent (empty)");
        defer benchmark.end();

        if (getRecent(allocator, setup.user.id, test_env.database, get_entry_recent)) |*entry_list| {
            const list = @constCast(entry_list);
            list.deinit();
        } else |err| {
            std.testing.expectEqual(error.EntriesNotFound, err) catch |inner_err| benchmark.fail(inner_err);
        }
    }
}

test "API Entry | Get average" {
    // SETUP
    const zdt = @import("zdt");
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    var setup = TestSetup.init(test_env.database, "API Entry | Get average") catch return error.TestSetupFailed;
    defer {
        setup.food.deinit(allocator);
        setup.user.deinit(allocator);
    }

    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    // Create Entries
    var date = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var date_string = std.ArrayList(u8).init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", date_string.writer());
    var create_entry = rq.PostEntry{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry_1 = try create(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    const entry_2 = try create(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    const entry_3 = try create(setup.user.id, test_env.database, create_entry);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .week));

    var lower_bound_string = std.ArrayList(u8).init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string = std.ArrayList(u8).init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.format("%Y-%m-%d", .{}, lower_bound_string.writer());
    try upper_bound.format("%Y-%m-%d", .{}, upper_bound_string.writer());

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    const get_entry_breakdown = rq.GetEntryBreakdown{
        .range_start = range_start,
        .range_end = range_end,
    };
    var expected_average = types.Nutrients{
        .calories = 0,
    };

    var unique_days = std.AutoHashMap(u16, void).init(allocator);
    defer unique_days.deinit();

    for ([_]Entry{ entry_1, entry_2, entry_3 }) |entry| {
        expected_average.calories += entry.amount * setup.food.nutrients.calories;
        const datetime = try zdt.Datetime.fromUnix(entry.created_at, .microsecond, null);
        try unique_days.put(datetime.dayOfYear(), {});
    }
    // TEST
    {
        var benchmark = Benchmark.start("API Entry | Get average");
        defer benchmark.end();

        const average = getAverage(setup.user.id, test_env.database, get_entry_breakdown) catch |err| {
            benchmark.fail(err);
            return err;
        };

        std.testing.expectEqual(expected_average.calories / @as(f64, @floatFromInt(unique_days.count())), average.calories) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(expected_average.added_sugars, average.added_sugars) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "API Entry | Get breakdown" {
    // SETUP
    const zdt = @import("zdt");
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    var setup = TestSetup.init(test_env.database, "API Entry | Get breakdown") catch return error.TestSetupFailed;
    defer {
        setup.food.deinit(allocator);
        setup.user.deinit(allocator);
    }

    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    // Create Entries
    var date = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var date_string = std.ArrayList(u8).init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", date_string.writer());
    var create_entry = rq.PostEntry{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry_1 = try create(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    const entry_2 = try create(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    const entry_3 = try create(setup.user.id, test_env.database, create_entry);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .week));

    var lower_bound_string = std.ArrayList(u8).init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string = std.ArrayList(u8).init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.format("%Y-%m-%d", .{}, lower_bound_string.writer());
    try upper_bound.format("%Y-%m-%d", .{}, upper_bound_string.writer());

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    const get_entry_breakdown = rq.GetEntryBreakdown{
        .range_start = range_start,
        .range_end = range_end,
    };
    var unique_days = std.AutoHashMap(u16, types.Nutrients).init(allocator);
    defer unique_days.deinit();

    for ([_]Entry{ entry_1, entry_2, entry_3 }) |entry| {
        const datetime = try zdt.Datetime.fromUnix(entry.created_at, .microsecond, null);
        const gop = try unique_days.getOrPut(datetime.dayOfYear());
        if (gop.found_existing) {
            gop.value_ptr.*.calories += entry.amount * setup.food.nutrients.calories;
        } else {
            gop.value_ptr.* = types.Nutrients{ .calories = entry.amount * setup.food.nutrients.calories };
        }
    }

    // TEST
    {
        var benchmark = Benchmark.start("API Entry | Get breakdown");
        defer benchmark.end();

        var breakdown = getBreakdown(allocator, setup.user.id, test_env.database, get_entry_breakdown) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer breakdown.deinit(allocator);

        std.testing.expectEqual(unique_days.count(), breakdown.list.len) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (breakdown.list) |day_breakdown| {
            const datetime = try zdt.Datetime.fromUnix(day_breakdown.created_at, .microsecond, null);
            const expected = unique_days.get(datetime.dayOfYear()).?;

            std.testing.expectEqual(expected.calories, day_breakdown.nutrients.calories) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(expected.added_sugars, day_breakdown.nutrients.added_sugars) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

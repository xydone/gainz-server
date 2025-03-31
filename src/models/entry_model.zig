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
};

pub const EntryList = struct {
    list: []Entry,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *EntryList) void {
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

    pub fn delete(ctx: *Handler.RequestContext, request: rq.DeleteEntry) anyerror!void {
        var conn = try ctx.app.db.acquire();
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
                    .allocator = allocator,
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

            try response.append(Entry{
                .id = entry_id,
                .food_id = food_id,
                .user_id = user_id,
                .serving_id = serving_id,
                .created_at = entry_created_at,
                .category = category,
                .amount = amount,
                .food = Food{
                    .id = food_id,
                    .allocator = allocator,
                    .brand_name = brand_name_duped,
                    .food_name = food_name_duped,
                    .nutrients = nutrients,
                    .created_at = food_created_at,
                },
            });
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
};

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

test "create entry" {
    const test_env = Tests.test_env;
    const create_entry = rq.PostEntry{ .food_id = 1, .category = .breakfast, .serving_id = 1, .amount = 0.5 };
    const entry = try Entry.create(1, test_env.database, create_entry);
    try std.testing.expectEqual(create_entry.food_id, entry.food_id);
    try std.testing.expectEqual(create_entry.serving_id, entry.serving_id);
    try std.testing.expectEqual(create_entry.amount, entry.amount);
    try std.testing.expectEqual(create_entry.category, entry.category);
}

test "get entry" {
    const test_env = Tests.test_env;
    const get_request = rq.GetEntry{ .entry = 1 };
    const entry = try Entry.get(1, test_env.database, get_request);

    try std.testing.expectEqual(1, entry.food_id);
    try std.testing.expectEqual(1, entry.serving_id);
    try std.testing.expectEqual(1, entry.user_id);
    try std.testing.expectEqual(types.MealCategory.breakfast, entry.category);
    try std.testing.expectEqual(0.5, entry.amount);
    try std.testing.expect(entry.food == null);
}
test "create multiple entries tests:noTime" {
    const zdt = @import("zdt");
    const test_env = Tests.test_env;

    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    var date = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var date_string = std.ArrayList(u8).init(test_env.allocator);
    try date.toString("%Y-%m-%d", date_string.writer());

    var create_entry = rq.PostEntry{ .food_id = 1, .category = .breakfast, .serving_id = 1, .amount = 1 };
    _ = try Entry.create(1, test_env.database, create_entry);
    create_entry.amount = 2.4;
    _ = try Entry.create(1, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    _ = try Entry.create(1, test_env.database, create_entry);
}

test "get entry range" {
    const zdt = @import("zdt");
    const test_env = Tests.test_env;

    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .day));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .day));

    var lower_bound_string = std.ArrayList(u8).init(test_env.allocator);
    var upper_bound_string = std.ArrayList(u8).init(test_env.allocator);

    try lower_bound.format("%Y-%m-%d", .{}, lower_bound_string.writer());
    try upper_bound.format("%Y-%m-%d", .{}, upper_bound_string.writer());

    const get_request = rq.GetEntryRange{
        .range_start = try lower_bound_string.toOwnedSlice(),
        .range_end = try upper_bound_string.toOwnedSlice(),
    };
    var entry_list = try Entry.getInRange(test_env.allocator, 1, test_env.database, get_request);
    defer entry_list.deinit();

    try std.testing.expectEqual(3, entry_list.list.len);

    //most recent one should be first
    try std.testing.expectEqual(2.4, entry_list.list[0].amount);
    try std.testing.expectEqual(1, entry_list.list[1].amount);
    try std.testing.expectEqual(0.5, entry_list.list[2].amount);
    try std.testing.expectEqual(1, entry_list.list[0].food.?.id);
    try std.testing.expectEqualStrings("Test brand", entry_list.list[0].food.?.brand_name.?);
    try std.testing.expectEqualStrings("Test food name", entry_list.list[0].food.?.food_name.?);
}
test "get entry range - empty" {
    const zdt = @import("zdt");
    const test_env = Tests.test_env;

    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    var lower_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(3, .day));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(3, .day));

    var lower_bound_string = std.ArrayList(u8).init(test_env.allocator);
    var upper_bound_string = std.ArrayList(u8).init(test_env.allocator);

    try lower_bound.format("%Y-%m-%d", .{}, lower_bound_string.writer());
    try upper_bound.format("%Y-%m-%d", .{}, upper_bound_string.writer());

    const get_request = rq.GetEntryRange{
        .range_start = try lower_bound_string.toOwnedSlice(),
        .range_end = try upper_bound_string.toOwnedSlice(),
    };
    var entry_list = Entry.getInRange(test_env.allocator, 1, test_env.database, get_request) catch |err| {
        return try std.testing.expectEqual(error.NotFound, err);
    };
    defer entry_list.deinit();
    return error.TestUnexpectedResult;
}

test "get entry recent - all" {
    const test_env = Tests.test_env;
    const get_entry_recent = rq.GetEntryRecent{
        .limit = 50,
    };
    var entry_list = try Entry.getRecent(test_env.allocator, 1, test_env.database, get_entry_recent);
    defer entry_list.deinit();

    try std.testing.expectEqual(4, entry_list.list.len);
    try std.testing.expectEqualStrings("Test brand", entry_list.list[0].food.?.brand_name.?);
}

test "get entry recent - partial" {
    const test_env = Tests.test_env;
    const get_entry_recent = rq.GetEntryRecent{
        .limit = 2,
    };
    var entry_list = try Entry.getRecent(test_env.allocator, 1, test_env.database, get_entry_recent);
    defer entry_list.deinit();

    try std.testing.expectEqual(2, entry_list.list.len);
    try std.testing.expectEqual(3, entry_list.list[0].id);
    try std.testing.expectEqual(2, entry_list.list[1].id);
}

test "get entry recent - empty" {
    const test_env = Tests.test_env;
    const get_entry_recent = rq.GetEntryRecent{
        .limit = 0,
    };
    var entry_list = Entry.getRecent(test_env.allocator, 1, test_env.database, get_entry_recent) catch |err| {
        return try std.testing.expectEqual(error.EntriesNotFound, err);
    };
    defer entry_list.deinit();
    return error.EntryListNotEmpty;
}

test "get entry average" {
    const zdt = @import("zdt");
    const test_env = Tests.test_env;
    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .week));

    var lower_bound_string = std.ArrayList(u8).init(test_env.allocator);
    var upper_bound_string = std.ArrayList(u8).init(test_env.allocator);

    try lower_bound.format("%Y-%m-%d", .{}, lower_bound_string.writer());
    try upper_bound.format("%Y-%m-%d", .{}, upper_bound_string.writer());

    const get_entry_breakdown = rq.GetEntryBreakdown{
        .range_start = try lower_bound_string.toOwnedSlice(),
        .range_end = try upper_bound_string.toOwnedSlice(),
    };
    const average = try Entry.getAverage(1, test_env.database, get_entry_breakdown);

    try std.testing.expectEqual(1102.5, average.calories);
    try std.testing.expectEqual(null, average.added_sugars);
}

test "get breakdown" {
    const zdt = @import("zdt");
    const test_env = Tests.test_env;
    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .day));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .day));

    var lower_bound_string = std.ArrayList(u8).init(test_env.allocator);
    var upper_bound_string = std.ArrayList(u8).init(test_env.allocator);

    try lower_bound.format("%Y-%m-%d", .{}, lower_bound_string.writer());
    try upper_bound.format("%Y-%m-%d", .{}, upper_bound_string.writer());

    const get_entry_breakdown = rq.GetEntryBreakdown{
        .range_start = try lower_bound_string.toOwnedSlice(),
        .range_end = try upper_bound_string.toOwnedSlice(),
    };
    const breakdown = try Entry.getBreakdown(test_env.allocator, 1, test_env.database, get_entry_breakdown);

    try std.testing.expectEqual(1, breakdown.list.len);
    try std.testing.expectEqual(now_day.toUnix(.microsecond), breakdown.list[0].created_at);
    try std.testing.expectEqual(1365.0, breakdown.list[0].nutrients.calories);
}

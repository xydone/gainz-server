const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");
const log = std.log.scoped(.entry_model);

pub fn get(ctx: *Handler.RequestContext, request: rq.GetEntry) anyerror!rs.GetEntry {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.get, //
        .{ ctx.user_id, request.entry }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;
    defer row.deinit() catch {};

    const id = row.get(i32, 0);
    const created_at = row.get(i64, 1);
    const user_id = row.get(i32, 2);
    const food_id = row.get(i32, 3);
    const meal_category = row.get(types.MealCategory, 4);
    const amount = row.get(f64, 5);
    const serving = row.get(i32, 6);
    return rs.GetEntry{ .created_at = created_at, .id = id, .user_id = user_id, .food_id = food_id, .category = meal_category, .amount = amount, .serving = serving };
}

pub fn getInRange(ctx: *Handler.RequestContext, request: rq.GetEntryRange) anyerror![]rs.GetEntryRange {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var result = conn.queryOpts(SQL_STRINGS.getInRange, .{ ctx.user_id, request.range_start, request.range_end }, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(rs.GetEntryRange).init(ctx.app.allocator);

    while (try result.next()) |row| {
        const created_at = row.getCol(i64, "created_at");
        const category = row.getCol(types.MealCategory, "category");
        const food_name = row.getCol([]u8, "food_name");
        const brand_name = row.getCol([]u8, "brand_name");
        const food_name_duped = if (food_name.len != 0) try ctx.app.allocator.dupe(u8, food_name) else null;
        const brand_name_duped = if (brand_name.len != 0) try ctx.app.allocator.dupe(u8, brand_name) else null;
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
        try response.append(rs.GetEntryRange{ .food_name = food_name_duped, .brand_name = brand_name_duped, .category = category, .created_at = created_at, .nutrients = nutrients });
    }
    return try response.toOwnedSlice();
}

pub fn getStats(ctx: *Handler.RequestContext, request: rq.GetEntryStats) anyerror!rs.GetEntryStats {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.rowOpts(SQL_STRINGS.getStats, //
        .{ ctx.user_id, request.range_start, request.range_end }, .{ .column_names = true }) catch |err| {
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

pub fn create(ctx: *Handler.RequestContext, request: rq.PostEntry) anyerror!rs.PostEntry {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.create, //
        .{ request.meal_category, request.food_id, ctx.user_id.?, request.amount, request.serving_id }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    //NOTE: you must deinitialize rows or else query time balloons 10x
    defer row.?.deinit() catch {};
    const id = row.?.get(i32, 0);
    const u_id = row.?.get(i32, 1);
    const f_id = row.?.get(i32, 2);
    const category = row.?.get(types.MealCategory, 3);

    return rs.PostEntry{ .id = id, .user_id = u_id, .food_id = f_id, .category = category };
}

const SQL_STRINGS = struct {
    pub const get = "SELECT * FROM entry WHERE user_id = $1 and id = $2;";
    pub const create = "insert into entry (category, food_id, user_id, amount, serving_id) values ($1,$2,$3,$4,$5) returning id, user_id, food_id, category;";
    pub const getInRange =
        \\SELECT e.id AS id,
        \\  e.created_at AS created_at,
        \\  f.brand_name as brand_name,
        \\  f.food_name as food_name,
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
    pub const getStats = "SELECT AVG(daily_calories) AS calories, AVG(daily_fat) AS fat, AVG(daily_sat_fat) AS sat_fat, AVG(daily_polyunsat_fat) AS polyunsat_fat, AVG(daily_monounsat_fat) AS monounsat_fat, AVG(daily_trans_fat) AS trans_fat, AVG(daily_cholesterol) AS cholesterol, AVG(daily_sodium) AS sodium, AVG(daily_potassium) AS potassium, AVG(daily_carbs) AS carbs, AVG(daily_fiber) AS fiber, AVG(daily_sugar) AS sugar, AVG(daily_protein) AS protein, AVG(daily_vitamin_a) AS vitamin_a, AVG(daily_vitamin_c) AS vitamin_c, AVG(daily_calcium) AS calcium, AVG(daily_iron) AS iron, AVG(daily_added_sugars) AS added_sugars, AVG(daily_vitamin_d) AS vitamin_d, AVG(daily_sugar_alcohols) AS sugar_alcohols FROM ( SELECT DATE(e.created_at) AS entry_date, SUM(e.amount * s.multiplier * f.calories / f.food_grams) AS daily_calories, SUM(e.amount * s.multiplier * f.fat / f.food_grams) AS daily_fat, SUM(e.amount * s.multiplier * f.sat_fat / f.food_grams) AS daily_sat_fat, SUM(e.amount * s.multiplier * f.polyunsat_fat / f.food_grams) AS daily_polyunsat_fat, SUM(e.amount * s.multiplier * f.monounsat_fat / f.food_grams) AS daily_monounsat_fat, SUM(e.amount * s.multiplier * f.trans_fat / f.food_grams) AS daily_trans_fat, SUM(e.amount * s.multiplier * f.cholesterol / f.food_grams) AS daily_cholesterol, SUM(e.amount * s.multiplier * f.sodium / f.food_grams) AS daily_sodium, SUM(e.amount * s.multiplier * f.potassium / f.food_grams) AS daily_potassium, SUM(e.amount * s.multiplier * f.carbs / f.food_grams) AS daily_carbs, SUM(e.amount * s.multiplier * f.fiber / f.food_grams) AS daily_fiber, SUM(e.amount * s.multiplier * f.sugar / f.food_grams) AS daily_sugar, SUM(e.amount * s.multiplier * f.protein / f.food_grams) AS daily_protein, SUM(e.amount * s.multiplier * f.vitamin_a / f.food_grams) AS daily_vitamin_a, SUM(e.amount * s.multiplier * f.vitamin_c / f.food_grams) AS daily_vitamin_c, SUM(e.amount * s.multiplier * f.calcium / f.food_grams) AS daily_calcium, SUM(e.amount * s.multiplier * f.iron / f.food_grams) AS daily_iron, SUM(e.amount * s.multiplier * f.added_sugars / f.food_grams) AS daily_added_sugars, SUM(e.amount * s.multiplier * f.vitamin_d / f.food_grams) AS daily_vitamin_d, SUM(e.amount * s.multiplier * f.sugar_alcohols / f.food_grams) AS daily_sugar_alcohols FROM entry e JOIN servings s ON e.serving_id = s.id JOIN food f ON e.food_id = f.id WHERE e.user_id = $1 AND Date(e.created_at) >= $2 AND Date(e.created_at) <= $3 GROUP BY entry_date ) AS daily_data";
};

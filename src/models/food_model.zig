const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.food_model);

pub fn get(ctx: *Handler.RequestContext, request: rq.GetFood) anyerror!rs.GetFood {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.rowOpts("SELECT * FROM food WHERE id = $1;", //
        .{request.food_id}, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;
    defer row.deinit() catch {};

    const id = row.get(i32, 0);
    const created_at = row.get(i64, 1);
    const macronutrients = types.Macronutrients{
        .calories = row.getCol(f64, "calories"),
        .fat = row.getCol(f64, "fat"),
        .sat_fat = row.getCol(f64, "sat_fat"),
        .polyunsat_fat = row.getCol(f64, "polyunsat_fat"),
        .monounsat_fat = row.getCol(f64, "monounsat_fat"),
        .trans_fat = row.getCol(f64, "trans_fat"),
        .cholesterol = row.getCol(f64, "cholesterol"),
        .sodium = row.getCol(f64, "sodium"),
        .potassium = row.getCol(f64, "potassium"),
        .carbs = row.getCol(f64, "carbs"),
        .fiber = row.getCol(f64, "fiber"),
        .sugar = row.getCol(f64, "sugar"),
        .protein = row.getCol(f64, "protein"),
        .vitamin_a = row.getCol(f64, "vitamin_a"),
        .vitamin_c = row.getCol(f64, "vitamin_c"),
        .calcium = row.getCol(f64, "calcium"),
        .iron = row.getCol(f64, "iron"),
    };
    const food_name = row.getCol([]u8, "food_name");
    const brand_name = row.getCol([]u8, "brand_name");
    return rs.GetFood{
        .id = id,
        .created_at = created_at,
        .food_name = food_name,
        .brand_name = brand_name,
        .macronutrients = macronutrients,
    };
}

pub fn search(ctx: *Handler.RequestContext, request: rq.SearchFood) anyerror![]rs.SearchFood {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var result = conn.queryOpts("SELECT f.*, JSON_AGG( CASE WHEN s.created_at IS NULL THEN NULL  ELSE json_build_object( 'id', s.id, 'amount', s.amount, 'unit', s.unit, 'multiplier', s.multiplier ) END ) AS servings FROM food f LEFT JOIN servings s ON f.id = s.food_id WHERE f.food_name ILIKE '%' || $1 || '%' OR f.brand_name ILIKE '%' || $1 || '%' GROUP BY f.id;", //
        .{request.search_term}, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(rs.SearchFood).init(ctx.app.allocator);
    while (try result.next()) |row| {
        const id = row.get(i32, 0);
        const created_at = row.get(i64, 1);

        const food_name = row.getCol([]u8, "food_name");
        const brand_name = row.getCol([]u8, "brand_name");
        const macronutrients = types.Macronutrients{
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
        const servings = std.json.parseFromSliceLeaky([]types.Servings, ctx.app.allocator, servings_unparsed, .{}) catch |err| {
            std.log.debug("{s}", .{servings_unparsed});
            std.log.debug("{}", .{err});
            return err;
        };

        // const servings = std.json.parseFromSliceLeaky(types.Servings, ctx.app.allocator,
        //     \\{"id":1240,"created_at":1737315796.863155,"amount":100,"unit":"gram","multiplier":1}
        // , .{}) catch |err| {
        //     std.log.debug("{s}", .{servings_unparsed});
        //     std.log.debug("{}", .{err});
        //     return err;
        // };
        try response.append(rs.SearchFood{
            .id = id,
            .created_at = created_at,
            .food_name = try ctx.app.allocator.dupe(u8, food_name),
            .brand_name = try ctx.app.allocator.dupe(u8, brand_name),
            .macronutrients = macronutrients,
            .servings = servings,
        });
    }
    return try response.toOwnedSlice();
}
pub fn create(ctx: *Handler.RequestContext, request: rq.PostFood) anyerror!rs.PostFood {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row("insert into food (created_by, brand_name, food_name, food_grams, calories, fat,sat_fat,polyunsat_fat,monounsat_fat,trans_fat,cholesterol,sodium,potassium,carbs,fiber,sugar,protein,vitamin_a,vitamin_c,calcium,iron ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21) returning id,brand_name,food_name", //
        .{ ctx.user_id.?, request.brand_name, request.food_name, request.macronutrients.calories, request.food_grams, request.macronutrients.fat, request.macronutrients.sat_fat, request.macronutrients.polyunsat_fat, request.macronutrients.monounsat_fat, request.macronutrients.trans_fat, request.macronutrients.cholesterol, request.macronutrients.sodium, request.macronutrients.potassium, request.macronutrients.carbs, request.macronutrients.fiber, request.macronutrients.sugar, request.macronutrients.protein, request.macronutrients.vitamin_a, request.macronutrients.vitamin_c, request.macronutrients.calcium, request.macronutrients.iron }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    //NOTE: you must deinitialize rows or else query time balloons 10x
    defer row.?.deinit() catch {};
    const id = row.?.get(i32, 0);
    const b_n = row.?.get(?[]u8, 1);
    const f_n = row.?.get(?[]u8, 2);

    const brand_name = if (b_n == null) null else try ctx.app.allocator.dupe(u8, b_n.?);
    const food_name = if (f_n == null) null else try ctx.app.allocator.dupe(u8, f_n.?);

    return rs.PostFood{ .id = id, .food_name = food_name, .brand_name = brand_name };
}

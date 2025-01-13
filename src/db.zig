const std = @import("std");

const pg = @import("pg");

const Handler = @import("handler.zig");
const rq = @import("request.zig");
const rs = @import("response.zig");
const types = @import("types.zig");
const auth = @import("util/auth.zig");
const dotenv = @import("util/dotenv.zig");
const redis = @import("util/redis.zig");

const ACCESS_TOKEN_EXPIRY = 60 * 30;
const REFRESH_TOKEN_EXPIRY = 7 * 24 * 60 * 60;

const EnvErrors = error{
    NoDatabaseHost,
    NoDatabaseName,
    NoDatabaseUsername,
    NoDatabasePassword,
};

const log = std.log.scoped(.database);
pub fn init(allocator: std.mem.Allocator, env: dotenv) !*pg.Pool {
    const database_host = env.get("DATABASE_HOST") orelse {
        return EnvErrors.NoDatabaseHost;
    };
    const database_name = env.get("DATABASE_NAME") orelse {
        return EnvErrors.NoDatabaseName;
    };
    const database_password = env.get("DATABASE_PASSWORD") orelse {
        return EnvErrors.NoDatabasePassword;
    };
    const database_username = env.get("DATABASE_USERNAME") orelse {
        return EnvErrors.NoDatabaseUsername;
    };
    const pool = try pg.Pool.init(allocator, .{ .size = 5, .connect = .{
        .port = 5432,
        .host = database_host,
    }, .auth = .{
        .username = database_username,
        .database = database_name,
        .password = database_password,
        .timeout = 10_000,
    } });
    return pool;
}

pub fn createUser(ctx: *Handler.RequestContext, request: rq.UserRequest) anyerror!rs.CreateUserResponse {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    const hashed_password = try auth.hashPassword(ctx.app.allocator, request.password);
    var row = conn.row("insert into users (display_name, username, password) values ($1,$2,$3) returning id,display_name", .{ request.display_name, request.username, hashed_password }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    //NOTE: you must deinitialize rows or else query time balloons 10x
    defer row.?.deinit() catch {};
    const id = row.?.get(i32, 0);
    const dn = row.?.get([]u8, 1);

    const dupe = try ctx.app.allocator.dupe(u8, dn);

    return rs.CreateUserResponse{ .id = id, .display_name = dupe };
}

pub fn createFood(ctx: *Handler.RequestContext, request: rq.FoodRequest) anyerror!rs.CreateFoodResponse {
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

    return rs.CreateFoodResponse{ .id = id, .food_name = food_name, .brand_name = brand_name };
}

pub fn createEntry(ctx: *Handler.RequestContext, request: rq.EntryRequest) anyerror!rs.CreateEntryResponse {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row("insert into entry (category, food_id, user_id, amount, serving_id) values ($1,$2,$3,$4,$5) returning id, user_id, food_id, category;", //
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

    return rs.CreateEntryResponse{ .id = id, .user_id = u_id, .food_id = f_id, .category = category };
}

pub fn createMeasurement(ctx: *Handler.RequestContext, request: rq.PostMeasurement) anyerror!rs.CreateMeasurementResponse {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row("insert into measurements (user_id,type, value) values ($1,$2,$3) returning created_at, type, value;", //
        .{ ctx.user_id, request.type, request.value }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    //NOTE: you must deinitialize rows or else query time balloons 10x
    defer row.?.deinit() catch {};
    const created_at = row.?.get(i64, 0);
    const measurement_type = row.?.get(types.MeasurementType, 1);
    const value = row.?.get(f64, 2);

    return rs.CreateMeasurementResponse{ .created_at = created_at, .type = measurement_type, .value = value };
}

pub fn getMeasurement(ctx: *Handler.RequestContext, request: rq.GetMeasurement) anyerror!rs.GetMeasurement {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row("SELECT * FROM measurements WHERE user_id = $1 AND id = $2", //
        .{ ctx.user_id.?, request.measurement_id }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;
    defer row.deinit() catch {};

    const id = row.get(i32, 0);
    const created_at = row.get(i64, 1);
    const measurement_type = row.get(types.MeasurementType, 2);
    const value = row.get(f64, 3);
    return rs.GetMeasurement{ .id = id, .created_at = created_at, .measurement_type = measurement_type, .value = value };
}

pub fn getMeasurementRange(ctx: *Handler.RequestContext, request: rq.GetMeasurementRange) anyerror![]rs.GetMeasurement {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var result = conn.query("SELECT * FROM measurements WHERE user_id = $1 AND created_at >= $2 AND created_at < $3 AND type = $4", //
        .{ ctx.user_id.?, request.range_start, request.range_end, request.measurement_type }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(rs.GetMeasurement).init(ctx.app.allocator);

    while (try result.next()) |row| {
        const id = row.get(i32, 0);
        const created_at = row.get(i64, 1);
        const measurement_type = row.get(types.MeasurementType, 2);
        const value = row.get(f64, 3);
        try response.append(rs.GetMeasurement{ .id = id, .created_at = created_at, .measurement_type = measurement_type, .value = value });
    }
    return try response.toOwnedSlice();
}

pub fn getEntry(ctx: *Handler.RequestContext, request: rq.GetEntryRequest) anyerror!rs.GetEntryResponse {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row("SELECT * FROM entry WHERE user_id = $1 and id = $2;", //
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
    return rs.GetEntryResponse{ .created_at = created_at, .id = id, .user_id = user_id, .food_id = food_id, .category = meal_category, .amount = amount, .serving = serving };
}

pub fn getFood(ctx: *Handler.RequestContext, request: rq.GetFoodRequest) anyerror!rs.GetFoodResponse {
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
    return rs.GetFoodResponse{
        .id = id,
        .created_at = created_at,
        .food_name = food_name,
        .brand_name = brand_name,
        .macronutrients = macronutrients,
    };
}

pub fn searchFood(ctx: *Handler.RequestContext, request: rq.SearchFoodRequest) anyerror![]rs.GetFoodResponse {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var result = conn.queryOpts("SELECT f.* FROM food f WHERE f.food_name ILIKE '%' || $1 || '%' OR f.brand_name ILIKE '%' || $1 || '%'", //
        .{request.search_term}, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(rs.GetFoodResponse).init(ctx.app.allocator);
    while (try result.next()) |row| {
        const id = row.get(i32, 0);
        const created_at = row.get(i64, 1);
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
        const food_name = row.getCol([]u8, "food_name");
        const brand_name = row.getCol([]u8, "brand_name");
        try response.append(rs.GetFoodResponse{
            .id = id,
            .created_at = created_at,
            .food_name = try ctx.app.allocator.dupe(u8, food_name),
            .brand_name = try ctx.app.allocator.dupe(u8, brand_name),
            .macronutrients = macronutrients,
        });
    }
    return try response.toOwnedSlice();
}

pub fn getServings(ctx: *Handler.RequestContext, request: rq.GetServingsRequest) anyerror![]rs.GetServingResponse {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var result = conn.queryOpts("SELECT * from servings WHERE food_id=$1", //
        .{request.food_id}, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(rs.GetServingResponse).init(ctx.app.allocator);

    while (try result.next()) |row| {
        const id = row.get(i32, 0);
        const created_at = row.get(i64, 1);
        const amount = row.get(f64, 3);
        const unit = row.get([]u8, 4);
        const multiplier = row.get(f64, 5);

        try response.append(rs.GetServingResponse{ .id = id, .created_at = created_at, .amount = amount, .unit = unit, .multiplier = multiplier });
    }
    return try response.toOwnedSlice();
}

pub fn getEntryRange(ctx: *Handler.RequestContext, request: rq.GetEntryRangeRequest) anyerror![]rs.GetEntryRangeResponse {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var result = conn.queryOpts("SELECT DATE_TRUNC($1, e.created_at) AS group_date, SUM(e.amount * s.multiplier * f.calories / f.food_grams ) AS calories, SUM(e.amount * s.multiplier * f.fat / f.food_grams) AS fat, SUM(e.amount * s.multiplier * f.sat_fat / f.food_grams ) AS sat_fat, SUM(e.amount * s.multiplier * f.polyunsat_fat / f.food_grams ) AS polyunsat_fat, SUM(e.amount * s.multiplier * f.monounsat_fat / f.food_grams ) AS monounsat_fat, SUM(e.amount * s.multiplier * f.trans_fat / f.food_grams ) AS trans_fat, SUM(e.amount * s.multiplier * f.cholesterol / f.food_grams ) AS cholesterol, SUM(e.amount * s.multiplier * f.sodium / f.food_grams) AS sodium, SUM(e.amount * s.multiplier * f.potassium / f.food_grams ) AS potassium, SUM(e.amount * s.multiplier * f.carbs / f.food_grams) AS carbs, SUM(e.amount * s.multiplier * f.fiber / f.food_grams) AS fiber, SUM(e.amount * s.multiplier * f.sugar / f.food_grams) AS sugar, SUM(e.amount * s.multiplier * f.protein / f.food_grams ) AS protein, SUM(e.amount * s.multiplier * f.vitamin_a / f.food_grams ) AS vitamin_a, SUM(e.amount * s.multiplier * f.vitamin_c / f.food_grams ) AS vitamin_c, SUM(e.amount * s.multiplier * f.calcium / f.food_grams ) AS calcium, SUM(e.amount * s.multiplier * f.iron / f.food_grams) AS iron, SUM(e.amount * s.multiplier * f.added_sugars / f.food_grams ) AS added_sugars, SUM(e.amount * s.multiplier * f.vitamin_d / f.food_grams ) AS vitamin_d, SUM(e.amount * s.multiplier * f.sugar_alcohols / f.food_grams ) AS sugar_alcohols FROM entry e JOIN servings s ON e.serving_id = s.id JOIN food f ON e.food_id = f.id WHERE e.user_id = $2 AND e.created_at >= $3 AND e.created_at < $4 GROUP BY group_date ORDER BY group_date DESC;", //
        .{ @tagName(request.group_type), ctx.user_id, request.range_start, request.range_end }, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(rs.GetEntryRangeResponse).init(ctx.app.allocator);

    while (try result.next()) |row| {
        const group_date = row.get(i64, 0);
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
        try response.append(rs.GetEntryRangeResponse{ .group_date = group_date, .macronutrients = macronutrients });
    }
    return try response.toOwnedSlice();
}

pub fn createToken(ctx: *Handler.RequestContext, request: rq.CreateTokenRequest) anyerror!rs.CreateTokenResponse {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row("SELECT id, password FROM users WHERE username=$1;", //
        .{request.username}) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;
    defer row.deinit() catch {};
    const user_id = row.get(i32, 0);
    const hash = row.get([]u8, 1);
    const isValidPassword = try auth.verifyPassword(ctx.app.allocator, hash, request.password);
    const claims = auth.JWTClaims{ .user_id = user_id, .exp = std.time.timestamp() + ACCESS_TOKEN_EXPIRY };
    const access_token = if (isValidPassword) try auth.createJWT(ctx.app.allocator, claims, ctx.app.env.get("JWT_SECRET").?) else return error.NotFound;
    const refresh_token = try auth.createSessionToken(ctx.app.allocator);
    _ = try ctx.app.redis_client.setWithExpiry(try std.fmt.allocPrint(ctx.app.allocator, "{}", .{user_id}), refresh_token, REFRESH_TOKEN_EXPIRY);
    return rs.CreateTokenResponse{ .access_token = access_token, .refresh_token = refresh_token, .expires_in = ACCESS_TOKEN_EXPIRY };
}

pub fn refreshToken(ctx: *Handler.RequestContext, request: rq.RefreshTokenRequest) anyerror!rs.CreateTokenResponse {
    var buf: [1024]u8 = undefined;
    const key = try std.fmt.bufPrint(&buf, "{}", .{request.user_id});
    const result = ctx.app.redis_client.get(key) catch |err| switch (err) {
        error.KeyValuePairNotFound => return error.NotFound,
        else => return error.MiscError,
    };
    if (!std.mem.eql(u8, result, ctx.refresh_token.?)) return error.NotFound;
    const claims = auth.JWTClaims{ .user_id = request.user_id, .exp = std.time.timestamp() + ACCESS_TOKEN_EXPIRY };

    const access_token = try auth.createJWT(ctx.app.allocator, claims, ctx.app.env.get("JWT_SECRET").?);

    return rs.CreateTokenResponse{ .access_token = access_token, .expires_in = ACCESS_TOKEN_EXPIRY, .refresh_token = ctx.refresh_token.? };
}

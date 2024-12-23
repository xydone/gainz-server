const std = @import("std");

const pg = @import("pg");

const rq = @import("request.zig");
const rs = @import("response.zig");
const types = @import("types.zig");
const dotenv = @import("util/dotenv.zig");

const EnvErrors = error{
    NoDatabaseHost,
    NoDatabaseName,
    NoDatabaseUsername,
    NoDatabasePassword,
};

const log = std.log.scoped(.database);
pub fn init(allocator: std.mem.Allocator) !*pg.Pool {
    var env = try dotenv.init(allocator, ".env");
    defer env.deinit();

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

pub fn createUser(app: *types.App, display_name: []u8) anyerror!rs.CreateUserResponse {
    var conn = try app.db.acquire();
    defer conn.release();
    var row = conn.row("insert into \"User\" (display_name) values ($1) returning id,display_name", .{display_name}) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    //NOTE: you must deinitialize rows or else query time balloons 10x
    defer row.?.deinit() catch {};
    const id = row.?.get(i32, 0);
    const dn = row.?.get([]u8, 1);

    const dupe = try app.allocator.dupe(u8, dn);

    return rs.CreateUserResponse{ .id = id, .display_name = dupe };
}

pub fn createFood(app: *types.App, request: rq.FoodRequest) anyerror!rs.CreateFoodResponse {
    var conn = try app.db.acquire();
    defer conn.release();
    var row = conn.row("insert into \"Food\" (created_by, brand_name, food_name, calories, fat,sat_fat,polyunsat_fat,monounsat_fat,trans_fat,cholesterol,sodium,potassium,carbs,fiber,sugar,protein,vitamin_a,vitamin_c,calcium,iron ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20) returning id,brand_name,food_name", //
        .{ request.user_id, request.brand_name, request.food_name, request.macronutrients.calories, request.macronutrients.fat, request.macronutrients.sat_fat, request.macronutrients.polyunsat_fat, request.macronutrients.monounsat_fat, request.macronutrients.trans_fat, request.macronutrients.cholesterol, request.macronutrients.sodium, request.macronutrients.potassium, request.macronutrients.carbs, request.macronutrients.fiber, request.macronutrients.sugar, request.macronutrients.protein, request.macronutrients.vitamin_a, request.macronutrients.vitamin_c, request.macronutrients.calcium, request.macronutrients.iron }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    //NOTE: you must deinitialize rows or else query time balloons 10x
    defer row.?.deinit() catch {};
    const id = row.?.get(i32, 0);
    const b_n = row.?.get([]u8, 1);
    const f_n = row.?.get([]u8, 2);

    return rs.CreateFoodResponse{ .id = id, .food_name = try app.allocator.dupe(u8, b_n), .brand_name = try app.allocator.dupe(u8, f_n) };
}

pub fn createEntry(app: *types.App, request: rq.EntryRequest) anyerror!rs.CreateEntryResponse {
    var conn = try app.db.acquire();
    defer conn.release();
    var row = conn.row("insert into \"Entry\" (\"category\", \"food_id\", \"user_id\") values ($1,$2,$3) returning id, user_id, food_id, category;", //
        .{ request.meal_category, request.food_id, request.user_id }) catch |err| {
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

pub fn createMeasurement(app: *types.App, request: rq.MeasurementRequest) anyerror!rs.CreateMeasurementResponse {
    var conn = try app.db.acquire();
    defer conn.release();
    var row = conn.row("insert into \"Measurement\" (\"user_id\",\"type\", \"value\") values ($1,$2,$3) returning created_at, type, value;", //
        .{ request.user_id, request.type, request.value }) catch |err| {
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

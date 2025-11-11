const log = std.log.scoped(.entry_model);

pub const Create = struct {
    pub const Request = struct {
        food_id: i32,
        category: types.MealCategory,
        amount: f64,
        serving_id: i32,
        created_at: ?[]const u8 = null,
    };
    pub const Response = struct {
        id: i32,
        user_id: i32,
        food_id: i32,
        serving_id: i32,
        created_at: i64,
        category: types.MealCategory,
        amount: f64,
    };
    pub const Errors = error{ CannotCreate, CannotParseResult } || DatabaseErrors;

    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var row = conn.row(query_string, //
            .{ request.category, request.food_id, user_id, request.amount, request.serving_id, request.created_at }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        //NOTE: you must deinitialize rows or else query time balloons 10x
        defer row.deinit() catch {};

        return row.to(Response, .{ .dupe = true }) catch return error.CannotParseResult;
    }

    const query_string =
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
};

pub const Delete = struct {
    pub const Request = struct {
        entry_id: u32,
    };
    pub const Response = struct {};
    pub const Errors = error{ CannotDelete, CannotParseResult } || DatabaseErrors;

    pub fn call(database: *Pool, request: Request) Errors!void {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const deleted = conn.exec(query_string, .{request.entry_id}) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotDelete;
        } orelse return error.CannotDelete;
        if (deleted == 0) return error.CannotDelete;
    }

    const query_string = "DELETE FROM entry WHERE id = $1";
};
pub const Edit = struct {
    pub const Request = struct {
        meal_category: types.MealCategory,
        amount: f64,
        serving_id: u32,
    };
    pub const Response = struct {};
    pub const Errors = error{ CannotEdit, CannotParseResult } || DatabaseErrors;

    pub fn call(database: *Pool, request: Request, entry_id: u32) Errors!void {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        const deleted = conn.exec(query_string, .{ entry_id, request.meal_category, request.amount, request.serving_id }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotEdit;
        } orelse return error.CannotEdit;
        if (deleted == 0) return error.CannotEdit;
    }

    const query_string = "UPDATE entry SET category = $2, amount = $3, serving_id = $4 WHERE id = $1;";
};

pub const Get = struct {
    pub const Request = struct {
        entry_id: u32,
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        user_id: i32,
        food_id: i32,
        category: types.MealCategory,
        amount: f64,
        serving_id: i32,
    };
    pub const Errors = error{ CannotGet, CannotParseResult } || DatabaseErrors;

    pub fn call(
        user_id: i32,
        database: *Pool,
        request: Request,
    ) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var row = conn.row(query_string, //
            .{ user_id, request.entry_id }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        } orelse return error.CannotGet;
        defer row.deinit() catch {};

        return row.to(Response, .{}) catch return error.CannotParseResult;
    }
    const query_string = "SELECT * FROM entry WHERE user_id = $1 and id = $2;";
};

pub const GetRecent = struct {
    pub const Request = struct { limit: u32 };
    pub const Response = struct {
        id: i32,
        user_id: i32,
        food_id: i32,
        serving_id: i32,
        created_at: i64,
        category: types.MealCategory,
        amount: f64,
        food: Food,

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            if (self.food.brand_name) |name| allocator.free(name);
            if (self.food.food_name) |name| allocator.free(name);
        }
    };

    pub const Errors = error{
        CannotGet,
        NoEntries,
        OutOfMemory,
        CannotParseResult,
    } || DatabaseErrors;

    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool, request: Request) Errors![]Response {
        var conn = database.acquire() catch return error.CannotGet;
        defer conn.release();
        var result = conn.queryOpts(query_string, .{ user_id, request.limit }, .{ .column_names = true, .allocator = allocator }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        };

        defer result.deinit();

        var response: std.ArrayList(Response) = .empty;
        while (result.next() catch return error.CannotGet) |row| {
            const entry_id = row.getCol(i32, "entry_id");
            const serving_id = row.getCol(i32, "serving_id");
            const food_id = row.getCol(i32, "id");
            const entry_created_at = row.getCol(i64, "entry_created_at");
            const food_created_at = row.getCol(i64, "created_at");
            const amount = row.getCol(f64, "amount");
            const food_name = std.fmt.allocPrint(allocator, "{?s}", .{row.getCol(?[]u8, "food_name")}) catch return error.OutOfMemory;
            const brand_name = std.fmt.allocPrint(allocator, "{?s}", .{row.getCol(?[]u8, "brand_name")}) catch return error.OutOfMemory;
            const nutrients = row.to(types.Nutrients, .{ .map = .name }) catch return error.CannotParseResult;
            try response.append(allocator, Response{
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
        if (response.items.len == 0) return error.NoEntries;
        return response.toOwnedSlice(allocator);
    }

    pub const query_string =
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
};

pub const GetInRange = struct {
    pub const Request = struct {
        /// datetime string (ex: 2024-01-01)
        range_start: []const u8,
        /// datetime string (ex: 2024-01-01)
        range_end: []const u8,
    };
    pub const Response = struct {
        id: i32,
        user_id: i32,
        food_id: i32,
        serving_id: i32,
        created_at: i64,
        category: types.MealCategory,
        amount: f64,
        food: Food,

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            if (self.food.brand_name) |name| allocator.free(name);
            if (self.food.food_name) |name| allocator.free(name);
        }
    };
    pub const Errors = error{
        CannotGet,
        NoEntries,
        OutOfMemory,
        CannotParseResult,
    } || DatabaseErrors;

    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool, request: Request) Errors![]Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var result = conn.queryOpts(query_string, .{ user_id, request.range_start, request.range_end }, .{ .column_names = true }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        };
        defer result.deinit();
        var response: std.ArrayList(Response) = .empty;
        defer response.deinit(allocator);

        while (result.next() catch return error.CannotGet) |row| {
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
            const nutrients = row.to(types.Nutrients, .{ .map = .name }) catch return error.CannotParseResult;

            const entry = Response{
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
            response.append(allocator, entry) catch return error.OutOfMemory;
        }
        if (response.items.len == 0) return error.NoEntries;
        return response.toOwnedSlice(allocator);
    }

    pub const query_string =
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
};

pub const GetAverage = struct {
    pub const Request = struct {
        /// datetime string (ex: 2024-01-01)
        range_start: []const u8,
        /// datetime string (ex: 2024-01-01)
        range_end: []const u8,
    };
    pub const Response = types.Nutrients;
    pub const Errors = error{
        CannotGet,
        NoEntries,
        OutOfMemory,
        CannotParseResult,
    } || DatabaseErrors;

    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var row = conn.rowOpts(query_string, //
            .{ user_id, request.range_start, request.range_end }, .{ .column_names = true }) catch |err| {
            std.debug.print("Error encountered: {}\n", .{err});
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        } orelse return error.CannotGet;
        defer row.deinit() catch {};
        // whenever the range is invalid, it returns one row of nulls, this is a check and a fix for that
        _ = row.getCol(?f64, "calories") orelse return error.CannotGet;
        return row.to(Response, .{}) catch return error.CannotParseResult;
    }

    pub const query_string = "SELECT AVG(daily_calories) AS calories, AVG(daily_fat) AS fat, AVG(daily_sat_fat) AS sat_fat, AVG(daily_polyunsat_fat) AS polyunsat_fat, AVG(daily_monounsat_fat) AS monounsat_fat, AVG(daily_trans_fat) AS trans_fat, AVG(daily_cholesterol) AS cholesterol, AVG(daily_sodium) AS sodium, AVG(daily_potassium) AS potassium, AVG(daily_carbs) AS carbs, AVG(daily_fiber) AS fiber, AVG(daily_sugar) AS sugar, AVG(daily_protein) AS protein, AVG(daily_vitamin_a) AS vitamin_a, AVG(daily_vitamin_c) AS vitamin_c, AVG(daily_calcium) AS calcium, AVG(daily_iron) AS iron, AVG(daily_added_sugars) AS added_sugars, AVG(daily_vitamin_d) AS vitamin_d, AVG(daily_sugar_alcohols) AS sugar_alcohols FROM ( SELECT DATE(e.created_at) AS entry_date, SUM(e.amount * s.multiplier * f.calories / f.food_grams) AS daily_calories, SUM(e.amount * s.multiplier * f.fat / f.food_grams) AS daily_fat, SUM(e.amount * s.multiplier * f.sat_fat / f.food_grams) AS daily_sat_fat, SUM(e.amount * s.multiplier * f.polyunsat_fat / f.food_grams) AS daily_polyunsat_fat, SUM(e.amount * s.multiplier * f.monounsat_fat / f.food_grams) AS daily_monounsat_fat, SUM(e.amount * s.multiplier * f.trans_fat / f.food_grams) AS daily_trans_fat, SUM(e.amount * s.multiplier * f.cholesterol / f.food_grams) AS daily_cholesterol, SUM(e.amount * s.multiplier * f.sodium / f.food_grams) AS daily_sodium, SUM(e.amount * s.multiplier * f.potassium / f.food_grams) AS daily_potassium, SUM(e.amount * s.multiplier * f.carbs / f.food_grams) AS daily_carbs, SUM(e.amount * s.multiplier * f.fiber / f.food_grams) AS daily_fiber, SUM(e.amount * s.multiplier * f.sugar / f.food_grams) AS daily_sugar, SUM(e.amount * s.multiplier * f.protein / f.food_grams) AS daily_protein, SUM(e.amount * s.multiplier * f.vitamin_a / f.food_grams) AS daily_vitamin_a, SUM(e.amount * s.multiplier * f.vitamin_c / f.food_grams) AS daily_vitamin_c, SUM(e.amount * s.multiplier * f.calcium / f.food_grams) AS daily_calcium, SUM(e.amount * s.multiplier * f.iron / f.food_grams) AS daily_iron, SUM(e.amount * s.multiplier * f.added_sugars / f.food_grams) AS daily_added_sugars, SUM(e.amount * s.multiplier * f.vitamin_d / f.food_grams) AS daily_vitamin_d, SUM(e.amount * s.multiplier * f.sugar_alcohols / f.food_grams) AS daily_sugar_alcohols FROM entry e JOIN servings s ON e.serving_id = s.id JOIN food f ON e.food_id = f.id WHERE e.user_id = $1 AND Date(e.created_at) >= $2 AND Date(e.created_at) <= $3 GROUP BY entry_date ) AS daily_data";
};

pub const GetBreakdown = struct {
    pub const Request = struct {
        /// datetime string (ex: 2024-01-01)
        range_start: []const u8,
        /// datetime string (ex: 2024-01-01)
        range_end: []const u8,
    };
    pub const Response = struct {
        created_at: i64,
        nutrients: types.Nutrients,
    };
    pub const Errors = error{
        CannotGet,
        NoEntries,
        OutOfMemory,
        CannotParseResult,
    } || DatabaseErrors;
    /// Caller must deinit
    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool, request: Request) Errors![]Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var result = conn.queryOpts(query_string, //
            .{ user_id, request.range_start, request.range_end }, .{ .column_names = true }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        };
        var response: std.ArrayList(Response) = .empty;
        while (result.next() catch return error.CannotGet) |row| {
            const entry_date = row.getCol(i64, "entry_date");
            const nutrients = row.to(types.Nutrients, .{ .map = .name }) catch return error.CannotParseResult;
            response.append(allocator, .{ .created_at = entry_date, .nutrients = nutrients }) catch return error.OutOfMemory;
        }
        if (response.items.len == 0) return error.NoEntries;
        return response.toOwnedSlice(allocator);
    }

    const query_string =
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
    pub fn init(database: *Pool, unique_name: []const u8) !TestSetup {
        const CreateFood = @import("food_model.zig").Create;
        const allocator = std.testing.allocator;

        // User insert
        const user = try createUser(database, unique_name);

        const create_food = CreateFood.Request{
            .brand_name = unique_name,
            .food_name = "Test food name",
            .food_grams = 100,
            .nutrients = types.Nutrients{ .calories = 350 },
        };

        return TestSetup{ .user = user, .food = try CreateFood.call(user.id, allocator, database, create_food) };
    }

    pub fn createUser(database: *Pool, name: []const u8) !User {
        return BaseTestSetup.createUser(database, name);
    }

    pub fn deinit(self: *TestSetup) void {
        self.user.deinit();
    }
};

test "API Entry | Create" {
    //SETUP
    const CreateFood = @import("food_model.zig").Create;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    var user = try TestSetup.createUser(test_env.database, "API Entry | Create");
    defer user.deinit(allocator);

    const brand = try std.fmt.allocPrint(allocator, "Test brand", .{});
    defer allocator.free(brand);
    const food_name = try std.fmt.allocPrint(allocator, "Test food name", .{});
    defer allocator.free(food_name);

    const create_food = CreateFood.Request{
        .brand_name = brand,
        .food_name = food_name,
        .food_grams = 100,
        .nutrients = types.Nutrients{ .calories = 350 },
    };
    var food = try CreateFood.call(user.id, allocator, test_env.database, create_food);
    defer food.deinit(allocator);

    const create_entry = Create.Request{
        .food_id = food.id,
        .category = .breakfast,
        .serving_id = food.servings.?[0].id,
        .amount = 0.5,
    };
    var entry_id: i32 = undefined;
    // TEST
    {
        const entry = try Create.call(user.id, test_env.database, create_entry);
        entry_id = entry.id;

        try std.testing.expectEqual(create_entry.food_id, entry.food_id);
        try std.testing.expectEqual(create_entry.serving_id, entry.serving_id);
        try std.testing.expectEqual(create_entry.amount, entry.amount);
        try std.testing.expectEqual(create_entry.category, entry.category);
    }
}

test "API Entry | Get" {
    //SETUP
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    var setup = TestSetup.init(test_env.database, "API Entry | Get") catch return error.TestSetupFailed;
    defer {
        setup.food.deinit(allocator);
        setup.user.deinit(allocator);
    }

    const create_entry = Create.Request{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry = try Create.call(setup.user.id, test_env.database, create_entry);
    // TEST
    {
        const result = try Get.call(
            setup.user.id,
            test_env.database,
            .{ .entry_id = @intCast(entry.id) },
        );

        try std.testing.expectEqual(entry.food_id, result.food_id);
        try std.testing.expectEqual(entry.serving_id, result.serving_id);
        try std.testing.expectEqual(entry.user_id, result.user_id);
        try std.testing.expectEqual(entry.category, result.category);
        try std.testing.expectEqual(entry.amount, result.amount);
    }
}

test "API Entry | Get range" {
    //SETUP
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
    var date_string = std.Io.Writer.Allocating.init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", &date_string.writer);
    // Create multiple entries
    var create_entry = Create.Request{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry_1 = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    const entry_2 = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    _ = try Create.call(setup.user.id, test_env.database, create_entry);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .day));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .day));

    var lower_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.toString("%Y-%m-%d", &lower_bound_string.writer);
    try upper_bound.toString("%Y-%m-%d", &upper_bound_string.writer);

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    const get_request = GetInRange.Request{
        .range_start = range_start,
        .range_end = range_end,
    };
    // TEST
    {
        const entry_list = try GetInRange.call(allocator, setup.user.id, test_env.database, get_request);
        defer {
            for (entry_list) |entry| {
                entry.deinit(allocator);
            }
            allocator.free(entry_list);
        }

        try std.testing.expectEqual(2, entry_list.len);

        // The most recently inserted entry in the range will appear first. Entry 3 is outside of the range
        const inserted_entries = [_]Create.Response{ entry_2, entry_1 };

        for (entry_list, inserted_entries) |entry, inserted| {
            try std.testing.expectEqual(inserted.id, entry.id);
            try std.testing.expectEqual(inserted.amount, entry.amount);
            try std.testing.expectEqual(setup.food.id, entry.food.id);
            try std.testing.expectEqualStrings(setup.food.brand_name.?, entry.food.brand_name.?);
            try std.testing.expectEqualStrings(setup.food.food_name.?, entry.food.food_name.?);
        }
    }
}
test "API Entry | Get range (empty)" {
    //SETUP
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
    var date_string = std.Io.Writer.Allocating.init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", &date_string.writer);
    // Create multiple entries
    var create_entry = Create.Request{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    _ = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    _ = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    _ = try Create.call(setup.user.id, test_env.database, create_entry);

    var lower_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(3, .day));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(3, .day));

    var lower_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.toString("%Y-%m-%d", &lower_bound_string.writer);
    try upper_bound.toString("%Y-%m-%d", &upper_bound_string.writer);

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    const get_request = GetInRange.Request{
        .range_start = range_start,
        .range_end = range_end,
    };
    // TEST
    {
        if (GetInRange.call(allocator, setup.user.id, test_env.database, get_request)) |*entry_list| {
            const list = @constCast(entry_list);
            for (list.*) |entry| {
                entry.deinit(allocator);
            }
        } else |err| {
            try std.testing.expectEqual(error.NoEntries, err);
        }
    }
}

test "API Entry | Get recent (all)" {
    //SETUP
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
    var date_string = std.Io.Writer.Allocating.init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", &date_string.writer);
    var create_entry = Create.Request{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry_1 = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    const entry_2 = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    const entry_3 = try Create.call(setup.user.id, test_env.database, create_entry);

    const limit: u32 = 50;
    // TEST
    {
        const entry_list = try GetRecent.call(allocator, setup.user.id, test_env.database, .{ .limit = limit });

        defer {
            for (entry_list) |entry| {
                entry.deinit(allocator);
            }
            allocator.free(entry_list);
        }

        // The entries are sorted by the created_at date
        // Meaning, the id or insert order wouldn't match the return
        const ordered_entries = [_]Create.Response{ entry_2, entry_1, entry_3 };
        try std.testing.expectEqual(ordered_entries.len, entry_list.len);

        for (entry_list, ordered_entries) |entry, ordered| {
            try std.testing.expectEqual(ordered.id, entry.id);
            try std.testing.expectEqual(ordered.amount, entry.amount);
            try std.testing.expectEqual(ordered.category, entry.category);
            try std.testing.expectEqual(ordered.serving_id, entry.serving_id);
            try std.testing.expectEqualStrings(setup.food.brand_name.?, entry.food.brand_name.?);
            try std.testing.expectEqualStrings(setup.food.food_name.?, entry.food.food_name.?);
        }
    }
}

test "API Entry | Get recent (partial)" {
    //SETUP
    const zdt = @import("zdt");
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
    var date_string = std.Io.Writer.Allocating.init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", &date_string.writer);
    var create_entry = Create.Request{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry_1 = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    const entry_2 = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    _ = try Create.call(setup.user.id, test_env.database, create_entry);

    const limit: u32 = 2;
    const inserted_entries = [_]Create.Response{ entry_2, entry_1 };
    // TEST
    {
        const entry_list = try GetRecent.call(allocator, setup.user.id, test_env.database, .{ .limit = limit });
        defer {
            for (entry_list) |entry| {
                entry.deinit(allocator);
            }
            allocator.free(entry_list);
        }
        try std.testing.expectEqual(inserted_entries.len, entry_list.len);
        for (entry_list, inserted_entries) |entry, inserted| {
            try std.testing.expectEqual(inserted.id, entry.id);
            try std.testing.expectEqual(inserted.amount, entry.amount);
            try std.testing.expectEqual(inserted.category, entry.category);
            try std.testing.expectEqual(inserted.serving_id, entry.serving_id);
            try std.testing.expectEqualStrings(setup.food.food_name.?, entry.food.food_name.?);
            try std.testing.expectEqualStrings(setup.food.brand_name.?, entry.food.brand_name.?);
        }
    }
}

test "API Entry | Get recent (empty)" {
    //SETUP
    const zdt = @import("zdt");
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
    var date_string = std.Io.Writer.Allocating.init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", &date_string.writer);
    var create_entry = Create.Request{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    _ = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    _ = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    _ = try Create.call(setup.user.id, test_env.database, create_entry);
    const limit: u32 = 0;
    // TEST
    {
        if (GetRecent.call(allocator, setup.user.id, test_env.database, .{ .limit = limit })) |*entry_list| {
            const list = @constCast(entry_list);
            for (list.*) |entry| {
                entry.deinit(allocator);
            }
        } else |err| {
            try std.testing.expectEqual(error.NoEntries, err);
        }
    }
}

test "API Entry | Get average" {
    // SETUP
    const zdt = @import("zdt");
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
    var date_string = std.Io.Writer.Allocating.init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", &date_string.writer);
    var create_entry = Create.Request{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry_1 = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    const entry_2 = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    const entry_3 = try Create.call(setup.user.id, test_env.database, create_entry);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .week));

    var lower_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.toString("%Y-%m-%d", &lower_bound_string.writer);
    try upper_bound.toString("%Y-%m-%d", &upper_bound_string.writer);

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    const get_entry_breakdown = GetAverage.Request{
        .range_start = range_start,
        .range_end = range_end,
    };
    var expected_average = types.Nutrients{
        .calories = 0,
    };

    var unique_days = std.AutoHashMap(u16, void).init(allocator);
    defer unique_days.deinit();

    for ([_]Create.Response{ entry_1, entry_2, entry_3 }) |entry| {
        expected_average.calories += entry.amount * setup.food.nutrients.calories;
        const datetime = try zdt.Datetime.fromUnix(entry.created_at, .microsecond, null);
        try unique_days.put(datetime.dayOfYear(), {});
    }
    // TEST
    {
        const average = try GetAverage.call(setup.user.id, test_env.database, get_entry_breakdown);

        try std.testing.expectEqual(expected_average.calories / @as(f64, @floatFromInt(unique_days.count())), average.calories);
        try std.testing.expectEqual(expected_average.added_sugars, average.added_sugars);
    }
}

test "API Entry | Get breakdown" {
    // SETUP
    const zdt = @import("zdt");
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
    var date_string = std.Io.Writer.Allocating.init(allocator);
    defer date_string.deinit();
    try date.toString("%Y-%m-%d", &date_string.writer);
    var create_entry = Create.Request{
        .food_id = setup.food.id,
        .category = .breakfast,
        .serving_id = setup.food.servings.?[0].id,
        .amount = 0.5,
    };

    const entry_1 = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.amount = 2.4;
    const entry_2 = try Create.call(setup.user.id, test_env.database, create_entry);
    create_entry.created_at = try date_string.toOwnedSlice();
    defer allocator.free(create_entry.created_at.?);

    const entry_3 = try Create.call(setup.user.id, test_env.database, create_entry);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .week));

    var lower_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.toString("%Y-%m-%d", &lower_bound_string.writer);
    try upper_bound.toString("%Y-%m-%d", &upper_bound_string.writer);

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    const get_entry_breakdown = GetBreakdown.Request{
        .range_start = range_start,
        .range_end = range_end,
    };
    var unique_days = std.AutoHashMap(u16, types.Nutrients).init(allocator);
    defer unique_days.deinit();

    for ([_]Create.Response{ entry_1, entry_2, entry_3 }) |entry| {
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
        const breakdown = try GetBreakdown.call(allocator, setup.user.id, test_env.database, get_entry_breakdown);
        defer allocator.free(breakdown);

        try std.testing.expectEqual(unique_days.count(), breakdown.len);
        for (breakdown) |day_breakdown| {
            const datetime = try zdt.Datetime.fromUnix(day_breakdown.created_at, .microsecond, null);
            const expected = unique_days.get(datetime.dayOfYear()).?;

            try std.testing.expectEqual(expected.calories, day_breakdown.nutrients.calories);
            try std.testing.expectEqual(expected.added_sugars, day_breakdown.nutrients.added_sugars);
        }
    }
}

const std = @import("std");

const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;
const Food = @import("food_model.zig").Food;

const Handler = @import("../handler.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

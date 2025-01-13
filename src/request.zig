const types = @import("types.zig");

pub const GetMeasurement = struct {
    measurement_id: u32,
};

pub const GetMeasurementRange = struct {
    measurement_type: types.MeasurementType,
    /// datetime string (ex: 2024-01-01)
    range_start: []const u8,
    /// datetime string (ex: 2024-01-01)
    range_end: []const u8,
};

pub const PostMeasurement = struct {
    type: types.MeasurementType,
    value: f64,
};

pub const EntryRequest = struct {
    food_id: i32,
    meal_category: types.MealCategory,
    amount: f64,
    serving_id: i32,
};

pub const FoodRequest = struct {
    brand_name: ?[]u8,
    food_name: ?[]u8,
    food_grams: f64,
    macronutrients: types.Macronutrients,
};

pub const UserRequest = struct {
    display_name: []u8,
    username: []u8,
    password: []u8,
};

pub const GetEntryRequest = struct {
    entry: u32,
};

pub const GetEntryRangeRequest = struct {
    group_type: types.DatePart,
    /// datetime string (ex: 2024-01-01)
    range_start: []const u8,
    /// datetime string (ex: 2024-01-01)
    range_end: []const u8,
};

pub const GetFoodRequest = struct {
    food_id: u32,
};

pub const SearchFoodRequest = struct {
    search_term: []const u8,
};

pub const GetServingsRequest = struct {
    food_id: i32,
};

pub const CreateTokenRequest = struct {
    username: []u8,
    password: []const u8,
};

pub const RefreshTokenRequest = struct {
    user_id: i32,
};

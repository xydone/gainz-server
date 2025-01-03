const types = @import("types.zig");

pub const MeasurementRequest = struct {
    user_id: i32,
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
    macronutrients: types.Macronutrients,
};

pub const UserRequest = struct { display_name: []u8 };

pub const GetEntryRequest = struct {
    user_id: i32,
    entry: i32,
};

pub const GetEntryRangeRequest = struct {
    user_id: i32,
    group_type: types.DatePart,
    /// datetime string (ex: 2024-01-01)
    range_start: []const u8,
    /// datetime string (ex: 2024-01-01)
    range_end: []const u8,
};

pub const GetFoodRequest = struct {
    user_id: i32,
    food_id: i32,
};

pub const SearchFoodRequest = struct {
    search_term: []const u8,
};

pub const GetServingsRequest = struct {
    food_id: i32,
};

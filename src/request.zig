const types = @import("types.zig");

pub const MeasurementRequest = struct {
    user_id: i32,
    type: types.MeasurementType,
    value: f32,
};

pub const EntryRequest = struct {
    user_id: i32,
    food_id: i32,
    meal_category: types.MealCategory,
};

pub const FoodRequest = struct {
    user_id: i32,
    brand_name: []u8,
    food_name: []u8,
    macronutrients: types.Macronutrients,
};

pub const UserRequest = struct { display_name: []u8 };

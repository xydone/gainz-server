const std = @import("std");

const types = @import("types.zig");

pub const CreateUserResponse = struct {
    id: i32,
    display_name: []u8,
};

pub const CreateFoodResponse = struct {
    id: i32,
    brand_name: ?[]u8,
    food_name: ?[]u8,
};

pub const CreateEntryResponse = struct {
    id: i32,
    user_id: i32,
    food_id: i32,
    category: types.MealCategory,
};

pub const CreateMeasurementResponse = struct {
    created_at: i64,
    type: types.MeasurementType,
    value: f64,
};

pub const GetMeasurement = struct {
    id: i32,
    created_at: i64,
    measurement_type: types.MeasurementType,
    value: f64,
};

pub const GetEntryResponse = struct {
    id: i32,
    created_at: i64,
    user_id: i32,
    food_id: i32,
    category: types.MealCategory,
    amount: f64,
    serving: i32,
};

pub const GetFoodResponse = struct {
    id: i32,
    created_at: i64,
    food_name: ?[]u8,
    brand_name: ?[]u8,
    macronutrients: types.Macronutrients,
};

pub const GetServingResponse = struct {
    id: i32,
    created_at: i64,
    amount: f64,
    unit: []u8,
    multiplier: f64,
};

pub const GetEntryRangeResponse = struct {
    group_date: i64,
    macronutrients: types.Macronutrients,
};

pub const CreateTokenResponse = struct {
    access_token: []const u8,
    refresh_token: []const u8,
    expires_in: i32,
};

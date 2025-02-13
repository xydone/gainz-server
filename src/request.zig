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

pub const PostEntry = struct {
    food_id: i32,
    meal_category: types.MealCategory,
    amount: f64,
    serving_id: i32,
};

pub const PostFood = struct {
    brand_name: ?[]u8,
    food_name: ?[]u8,
    food_grams: f64,
    macronutrients: types.Macronutrients,
};

pub const PostUser = struct {
    display_name: []u8,
    username: []u8,
    password: []u8,
};

pub const GetEntry = struct {
    entry: u32,
};

pub const GetEntryRange = struct {
    /// datetime string (ex: 2024-01-01)
    range_start: []const u8,
    /// datetime string (ex: 2024-01-01)
    range_end: []const u8,
};

pub const GetEntryStats = struct {
    /// datetime string (ex: 2024-01-01)
    range_start: []const u8,
    /// datetime string (ex: 2024-01-01)
    range_end: []const u8,
};

pub const GetFood = struct {
    food_id: u32,
};

pub const SearchFood = struct {
    search_term: []const u8,
};

pub const GetServings = struct {
    food_id: i32,
};

pub const PostAuth = struct {
    username: []u8,
    password: []const u8,
};

pub const PostNote = struct {
    title: []const u8,
    description: ?[]const u8,
};

pub const GetNote = struct {
    id: u32,
};

pub const GetNoteRange = struct {
    note_id: u32,
    /// datetime string (ex: 2024-01-01)
    range_start: []const u8,
    /// datetime string (ex: 2024-01-01)
    range_end: []const u8,
};

pub const PostNoteEntry = struct {
    note_id: u32,
};

pub const RefreshAccessToken = struct {
    refresh_token: []const u8,
};

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

pub const DeleteMeasurement = struct {
    measurement_id: i32,
};

pub const GetMeasurementRecent = struct {
    measurement_type: types.MeasurementType,
};

pub const PostMeasurement = struct {
    type: types.MeasurementType,
    value: f64,
    date: ?[]const u8 = null,
};

pub const PostEntry = struct {
    food_id: i32,
    category: types.MealCategory,
    amount: f64,
    serving_id: i32,
    created_at: ?[]const u8 = null,
};

pub const GetEntry = struct {
    entry: u32,
};

pub const DeleteEntry = struct {
    id: u32,
};

pub const EditEntry = struct {
    meal_category: types.MealCategory,
    amount: f64,
    serving_id: i32,
};

pub const GetEntryRecent = struct {
    limit: u32,
};

pub const GetEntryRange = struct {
    /// datetime string (ex: 2024-01-01)
    range_start: []const u8,
    /// datetime string (ex: 2024-01-01)
    range_end: []const u8,
};

pub const GetEntryBreakdown = struct {
    /// datetime string (ex: 2024-01-01)
    range_start: []const u8,
    /// datetime string (ex: 2024-01-01)
    range_end: []const u8,
};

pub const PostServings = struct {
    food_id: i32,
    amount: f64,
    unit: []const u8,
    multiplier: f64,
};

pub const GetServings = struct {
    food_id: i32,
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

pub const PostUnit = struct {
    amount: f64,
    unit: []u8,
    multiplier: f64,
    exercise_id: u32,
};

pub const PostGoal = struct {
    target: types.GoalTargets,
    value: f64,
};

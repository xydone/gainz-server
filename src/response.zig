const std = @import("std");

const types = @import("types.zig");
const httpz = @import("httpz");

pub const ResponseError = struct {
    code: u16,
    message: []const u8,
    details: ?[]const u8 = null,

    // 400
    pub const bad_request: ResponseError = .{
        .code = 400,
        .message = "Bad request.",
    };
    pub const body_missing: ResponseError = .{
        .code = 400,
        .message = "The request body is not found.",
    };
    pub const body_missing_fields: ResponseError = .{
        .code = 400,
        .message = "The request body is missing required fields.",
    };
    pub const unauthorized: ResponseError = .{
        .code = 401,
        .message = "You are not authorized to make this request.",
    };

    pub const not_found: ResponseError = .{
        .code = 404,
        .message = "Not found.",
    };

    // 500
    pub const internal_server_error: ResponseError = .{
        .code = 500,
        .message = "An unexpected error occurred on the server. Please try again later.",
    };
};

pub fn handleResponse(httpz_res: *httpz.Response, response_error: ResponseError, details: ?[]const u8) !void {
    var response = response_error;
    response.details = details orelse null;
    httpz_res.status = response.code;
    try httpz_res.json(response, .{ .emit_null_optional_fields = false });
    return;
}

pub const PostUser = struct {
    id: i32,
    display_name: []u8,
};

pub const PostFood = struct {
    id: i32,
    brand_name: ?[]u8,
    food_name: ?[]u8,
};

pub const PostEntry = struct {
    id: i32,
    user_id: i32,
    food_id: i32,
    category: types.MealCategory,
};

pub const PostMeasurement = struct {
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

pub const GetEntry = struct {
    id: i32,
    created_at: i64,
    user_id: i32,
    food_id: i32,
    category: types.MealCategory,
    amount: f64,
    serving: i32,
};

pub const GetFood = struct {
    id: i32,
    created_at: i64,
    food_name: ?[]u8,
    brand_name: ?[]u8,
    macronutrients: types.Macronutrients,
};

pub const GetServing = struct {
    id: i32,
    created_at: i64,
    amount: f64,
    unit: []u8,
    multiplier: f64,
};

pub const GetEntryRange = struct {
    created_at: i64,
    category: types.MealCategory,
    food_name: ?[]u8,
    brand_name: ?[]u8,
    macronutrients: types.Macronutrients,
};

pub const GetEntryStats = struct {
    group_date: i64,
    macronutrients: types.Macronutrients,
};

pub const CreateToken = struct {
    display_name: []const u8,
    access_token: []const u8,
    refresh_token: []const u8,
    expires_in: i32,
};

pub const RefreshToken = struct {
    access_token: []const u8,
    refresh_token: []const u8,
    expires_in: i32,
};

pub const PostNote = struct {
    id: i32,
    title: []const u8,
    description: []const u8,
};

pub const GetNote = struct {
    id: i32,
    title: []const u8,
    description: []const u8,
};

pub const PostNoteEntry = struct {
    id: i32,
    created_by: i32,
    note_id: i32,
};

pub const GetNoteEntry = struct {
    id: i32,
    created_by: i32,
    note_id: i32,
    created_at: i64,
};

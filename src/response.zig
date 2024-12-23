const std = @import("std");

const types = @import("types.zig");

pub const CreateUserResponse = struct {
    id: i32,
    display_name: []u8,
    pub fn format(s: CreateUserResponse, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("CreateUserResponse{{ id: {d}, name: {s} }}", .{ s.id, s.display_name });
    }
};

pub const CreateFoodResponse = struct {
    id: i32,
    brand_name: []u8,
    food_name: []u8,

    pub fn format(s: CreateFoodResponse, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("CreateFoodResponse{{ id: {d}, food_name: {s}, brand_name: {s} }}", .{ s.id, s.food_name, s.brand_name });
    }
};

pub const CreateEntryResponse = struct {
    id: i32,
    user_id: i32,
    food_id: i32,
    category: types.MealCategory,

    pub fn format(s: CreateEntryResponse, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("CreateEntryResponse{{ id: {d}, user_id: {d}, food_id: {d}, category: {}, }}", .{ s.id, s.user_id, s.food_id, s.category });
    }
};

pub const CreateMeasurementResponse = struct {
    created_at: i64,
    type: types.MeasurementType,
    value: f64,

    pub fn format(s: CreateMeasurementResponse, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("CreateMeasurementResponse{{ id: {d}, user_id: {d}, food_id: {d}, category: {}, }}", .{ s.id, s.user_id, s.food_id, s.category });
    }
};

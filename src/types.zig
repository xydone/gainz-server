const std = @import("std");

const pg = @import("pg");

pub const App = struct {
    db: *pg.Pool,
    allocator: std.mem.Allocator,
};

pub const Macronutrients = struct {
    calories: f32,
    //the reason why we set the following ones to default as null is because std.json.parseFromSlice(...) will just be unable to parse fields with either missing, which are not defaulted
    fat: ?f32 = null,
    sat_fat: ?f32 = null,
    polyunsat_fat: ?f32 = null,
    monounsat_fat: ?f32 = null,
    trans_fat: ?f32 = null,
    cholesterol: ?f32 = null,
    sodium: ?f32 = null,
    potassium: ?f32 = null,
    carbs: ?f32 = null,
    fiber: ?f32 = null,
    sugar: ?f32 = null,
    protein: ?f32 = null,
    vitamin_a: ?f32 = null,
    vitamin_c: ?f32 = null,
    calcium: ?f32 = null,
    iron: ?f32 = null,
};

pub const MeasurementType = enum { weight, waist, hips, neck };

pub const MealCategory = enum { breakfast, lunch, dinner, misc };

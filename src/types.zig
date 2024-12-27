const std = @import("std");

const httpz = @import("httpz");
const pg = @import("pg");

pub const App = struct {
    db: *pg.Pool,
    allocator: std.mem.Allocator,
};

pub const Macronutrients = struct {
    calories: f64,
    //the reason why we set the following ones to default as null is because std.json.parseFromSlice(...) will just be unable to parse fields with either missing, which are not defaulted
    fat: ?f64 = null,
    sat_fat: ?f64 = null,
    polyunsat_fat: ?f64 = null,
    monounsat_fat: ?f64 = null,
    trans_fat: ?f64 = null,
    cholesterol: ?f64 = null,
    sodium: ?f64 = null,
    potassium: ?f64 = null,
    carbs: ?f64 = null,
    fiber: ?f64 = null,
    sugar: ?f64 = null,
    protein: ?f64 = null,
    vitamin_a: ?f64 = null,
    vitamin_c: ?f64 = null,
    calcium: ?f64 = null,
    iron: ?f64 = null,
    added_sugars: ?f64 = null,
    vitamin_d: ?f64 = null,
    sugar_alcohols: ?f64 = null,
};

pub const MeasurementType = enum { weight, waist, hips, neck };

pub const MealCategory = enum { breakfast, lunch, dinner, misc };

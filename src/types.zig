const std = @import("std");

const httpz = @import("httpz");
const pg = @import("pg");

pub const App = struct {
    db: *pg.Pool,
    allocator: std.mem.Allocator,
};

pub const GoalTargets = enum {
    weight,
    calories,
    fat,
    sat_fat,
    polyunsat_fat,
    monounsat_fat,
    trans_fat,
    cholesterol,
    sodium,
    potassium,
    carbs,
    fiber,
    sugar,
    protein,
    vitamin_a,
    vitamin_c,
    calcium,
    iron,
    added_sugars,
    vitamin_d,
    sugar_alcohols,
};

pub const Nutrients = struct {
    calories: f64,
    //the reason why we set the following ones to default as null is because std.json.parseFromSliceLeaky(...) will just be unable to parse fields with either missing, which are not defaulted
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

pub const Servings = struct {
    id: i32,
    amount: f64,
    unit: []u8,
    multiplier: f64,

    pub fn format(
        self: Servings,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt; // autofix
        _ = options; // autofix
        try writer.writeAll("Servings{ ");
        try writer.print(".id = {d}, .amount = {d}, .unit = \"{s}\", .multiplier = {d}", .{
            self.id, self.amount, self.unit, self.multiplier,
        });
        try writer.writeAll(" }");
    }
};
//TODO: dynamically load them in?
pub const MeasurementType = enum { weight, waist, hips, neck, height };

pub const MealCategory = enum { breakfast, lunch, dinner, misc };

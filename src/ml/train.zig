pub const Data = struct {
    calories: f32,
    carbs: f32,
    sugar: f32,
    protein: f32,
    weight: f32,
};

const Features = struct {
    calories_rolling: f32,
    carbs_rolling: f32,
    sugar_rolling: f32,
    protein_rolling: f32,
    weight: f32,
};

pub const Response = struct {
    r2: f32,
    mae: f32,
    created_at: i64,
};

pub const Errors = error{ CouldntSaveModel, XGBoostError, OutOfMemory };

pub fn run(allocator: std.mem.Allocator, user_id: i32, data: []Data) Errors!Response {
    var calories = try allocator.alloc(f32, data.len);
    defer allocator.free(calories);
    var carbs = try allocator.alloc(f32, data.len);
    defer allocator.free(carbs);
    var sugar = try allocator.alloc(f32, data.len);
    defer allocator.free(sugar);
    var protein = try allocator.alloc(f32, data.len);
    defer allocator.free(protein);

    for (data, 0..) |record, i| {
        calories[i] = record.calories;
        carbs[i] = record.carbs;
        sugar[i] = record.sugar;
        protein[i] = record.protein;
    }

    const rolling_window = 7;
    const calories_rolling = try rollingMean(allocator, calories, rolling_window);
    defer allocator.free(calories_rolling);
    const carbs_rolling = try rollingMean(allocator, carbs, rolling_window);
    defer allocator.free(carbs_rolling);
    const sugar_rolling = try rollingMean(allocator, sugar, rolling_window);
    defer allocator.free(sugar_rolling);
    const protein_rolling = try rollingMean(allocator, protein, rolling_window);
    defer allocator.free(protein_rolling);

    var processed_data = std.ArrayList(Features).empty;
    defer processed_data.deinit(allocator);

    for (data, 0..) |record, i| {
        try processed_data.append(allocator, .{
            .calories_rolling = calories_rolling[i],
            .carbs_rolling = carbs_rolling[i],
            .sugar_rolling = sugar_rolling[i],
            .protein_rolling = protein_rolling[i],
            .weight = record.weight,
        });
    }

    const shuffled_data = try allocator.alloc(Features, processed_data.items.len);

    const split = try trainTestSplit(shuffled_data, processed_data.items, 0.2, 42);
    const train_data = split.train;
    const test_data = split.@"test";

    // Prepare data for XGBoost
    const num_features = 4;
    var train_features = try allocator.alloc(f32, train_data.len * num_features);
    defer allocator.free(train_features);
    var train_labels = try allocator.alloc(f32, train_data.len);
    defer allocator.free(train_labels);

    for (train_data, 0..) |record, i| {
        train_features[i * num_features + 0] = record.calories_rolling;
        train_features[i * num_features + 1] = record.carbs_rolling;
        train_features[i * num_features + 2] = record.sugar_rolling;
        train_features[i * num_features + 3] = record.protein_rolling;
        train_labels[i] = record.weight;
    }

    var test_features = try allocator.alloc(f32, test_data.len * num_features);
    defer allocator.free(test_features);
    var test_labels = try allocator.alloc(f32, test_data.len);
    defer allocator.free(test_labels);

    for (test_data, 0..) |record, i| {
        test_features[i * num_features + 0] = record.calories_rolling;
        test_features[i * num_features + 1] = record.carbs_rolling;
        test_features[i * num_features + 2] = record.sugar_rolling;
        test_features[i * num_features + 3] = record.protein_rolling;
        test_labels[i] = record.weight;
    }

    // matrices for training and testing
    const dtrain = try XGBoost.DMatrix.initFromMatrix(train_features, train_data.len, num_features, -1, .{});
    defer dtrain.deinit();
    try dtrain.setFloatInfo("label", train_labels);

    const dtest = try XGBoost.DMatrix.initFromMatrix(test_features, test_data.len, num_features, -1, .{});
    defer dtest.deinit();
    try dtest.setFloatInfo("label", test_labels);

    // train
    var dmats = [_]XGBoost.DMatrix.DMatrixHandle{ dtrain.handle, dtest.handle };
    const booster = try XGBoost.Booster.init(&dmats, dmats.len);
    defer booster.deinit();

    try booster.setParam("objective", "reg:squarederror");

    // training with 100 estimators
    for (0..100) |i| {
        try booster.updateOneIter(@intCast(i), dtrain);
    }

    // predict
    const y_pred = try booster.predict(dtest, 0, 0, 0);

    const r2 = r2Score(test_labels, y_pred);
    const mae = meanAbsoluteError(test_labels, y_pred);

    const created_at = std.time.microTimestamp();

    const file_path = try std.fmt.allocPrint(allocator, "./models/model_{}_{}.ubj", .{ user_id, created_at });
    defer allocator.free(file_path);

    // XGBoost's saveModel requires the folder to already be created
    // if ./models cannot be opened, assume it is not present and create it
    _ = std.fs.cwd().openDir("./models", .{}) catch {
        std.fs.cwd().makeDir("./models") catch return error.CouldntSaveModel;
    };

    booster.saveModel(file_path) catch return error.CouldntSaveModel;

    return .{
        .r2 = r2,
        .mae = mae,
        .created_at = created_at,
    };
}

fn rollingMean(allocator: std.mem.Allocator, data: []const f32, window_size: usize) ![]f32 {
    var results = try allocator.alloc(f32, data.len);
    for (data, 0..) |_, i| {
        const start = if (i < window_size) 0 else i - window_size + 1;
        const window = data[start .. i + 1];
        var sum: f32 = 0;
        for (window) |val| {
            sum += val;
        }
        results[i] = sum / @as(f32, @floatFromInt(window.len));
    }
    return results;
}

fn trainTestSplit(
    shuffled_data: []Features,
    data: []Features,
    test_size: f32,
    random_seed: u64,
) !struct { train: []const Features, @"test": []const Features } {
    @memcpy(shuffled_data, data);
    var prng = std.Random.DefaultPrng.init(random_seed);
    const rand = prng.random();
    rand.shuffle(Features, shuffled_data);

    const test_count = @as(u32, @intFromFloat(@round(test_size * @as(f32, @floatFromInt(data.len)))));
    const train_count = data.len - test_count;

    return .{
        .train = shuffled_data[0..train_count],
        .@"test" = shuffled_data[train_count..],
    };
}

fn r2Score(actual: []const f32, predicted: []const f32) f32 {
    var sum_actual: f32 = 0;
    for (actual) |y| {
        sum_actual += y;
    }
    const mean_actual = sum_actual / @as(f32, @floatFromInt(actual.len));

    var ss_total: f32 = 0;
    var ss_res: f32 = 0;
    for (actual, 0..) |y_true, i| {
        const y_pred = predicted[i];
        ss_total += (y_true - mean_actual) * (y_true - mean_actual);
        ss_res += (y_true - y_pred) * (y_true - y_pred);
    }

    return 1 - (ss_res / ss_total);
}

fn meanAbsoluteError(actual: []const f32, predicted: []const f32) f32 {
    var sum_abs_error: f32 = 0;
    for (actual, 0..) |y_true, i| {
        sum_abs_error += @abs(y_true - predicted[i]);
    }
    return sum_abs_error / @as(f32, @floatFromInt(actual.len));
}

const XGBoost = @import("xgboost");
const std = @import("std");

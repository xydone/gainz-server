pub const Data = struct {
    calories: f32,
    carbs: f32,
    sugar: f32,
    protein: f32,
    sodium: f32,
    weight: f32,
};

pub const Windows = struct {
    short: usize,
    long: usize,
};

pub const Features = struct {
    /// short timespan, for example a 3 day rolling average
    calories_rolling_short: f32,

    /// slightly longer timespan, for example a 7 day rolling average
    calories_rolling_long: f32,
    carbs_rolling_long: f32,
    sugar_rolling_long: f32,
    protein_rolling_long: f32,
    sodium_rolling_long: f32,

    /// weight from yesterday
    previous_weight: f32,
    weight_delta: f32,
    weight: f32,

    fn fromData(allocator: std.mem.Allocator, data: []Data, windows: Windows) ![]Features {
        const Metrics = struct {
            calories: []f32,
            carbs: []f32,
            sugar: []f32,
            protein: []f32,
            sodium: []f32,
        };
        var metrics: Metrics = undefined;

        inline for (@typeInfo(Metrics).@"struct".fields) |field| {
            @field(metrics, field.name) = try allocator.alloc(f32, data.len);
        }
        defer {
            inline for (@typeInfo(Metrics).@"struct".fields) |field| {
                allocator.free(@field(metrics, field.name));
            }
        }

        for (data, 0..) |record, i| {
            metrics.calories[i] = record.calories;
            metrics.carbs[i] = record.carbs;
            metrics.sugar[i] = record.sugar;
            metrics.protein[i] = record.protein;
            metrics.sodium[i] = record.sodium;
        }

        const RollingMeans = struct {
            calories_rolling_short: []f32,
            calories_rolling_long: []f32,
            carbs_rolling_long: []f32,
            sugar_rolling_long: []f32,
            protein_rolling_long: []f32,
            sodium_rolling_long: []f32,
        };
        const rolling_means: RollingMeans = .{
            .calories_rolling_short = try rollingMean(allocator, metrics.calories, windows.short),
            .calories_rolling_long = try rollingMean(allocator, metrics.calories, windows.long),
            .carbs_rolling_long = try rollingMean(allocator, metrics.carbs, windows.long),
            .protein_rolling_long = try rollingMean(allocator, metrics.protein, windows.long),
            .sugar_rolling_long = try rollingMean(allocator, metrics.sugar, windows.long),
            .sodium_rolling_long = try rollingMean(allocator, metrics.sodium, windows.long),
        };
        defer {
            inline for (@typeInfo(RollingMeans).@"struct".fields) |field| {
                allocator.free(@field(rolling_means, field.name));
            }
        }

        var processed_data = std.ArrayList(Features).empty;
        defer processed_data.deinit(allocator);

        // start at 1 as we don't know the previous weight of the first element
        for (data[1..], 1..) |record, i| {
            try processed_data.append(allocator, .{
                .calories_rolling_short = rolling_means.calories_rolling_short[i - 1],
                .calories_rolling_long = rolling_means.calories_rolling_long[i - 1],
                .carbs_rolling_long = rolling_means.carbs_rolling_long[i - 1],
                .sugar_rolling_long = rolling_means.sugar_rolling_long[i - 1],
                .protein_rolling_long = rolling_means.protein_rolling_long[i - 1],
                .sodium_rolling_long = rolling_means.sodium_rolling_long[i - 1],
                .previous_weight = data[i - 1].weight,
                .weight_delta = record.weight - data[i - 1].weight,
                .weight = record.weight,
            });
        }

        return processed_data.toOwnedSlice(allocator);
    }
};
pub const Train = struct {
    pub const Response = struct {
        r2: f32,
        mae: f32,
        created_at: i64,
    };

    pub const Errors = error{ CouldntSaveModel, XGBoostError, OutOfMemory };

    pub fn run(allocator: std.mem.Allocator, absolute_path: []const u8, user_id: i32, data: []Data) Errors!Response {
        const processed_data = try Features.fromData(allocator, data, .{
            .long = 7,
            .short = 3,
        });
        defer allocator.free(processed_data);

        const split = try trainTestSplit(processed_data, 0.3);
        const train_data = split.train;
        const test_data = split.@"test";

        const dtrain, const train_labels = try createMatrix(allocator, train_data);
        defer {
            dtrain.deinit();
            allocator.free(train_labels);
        }
        const dtest, const test_labels = try createMatrix(allocator, test_data);
        defer {
            dtest.deinit();
            allocator.free(test_labels);
        }

        var dmats = [_]XGBoost.DMatrix.DMatrixHandle{ dtrain.handle, dtest.handle };
        const booster = try XGBoost.Booster.init(&dmats, dmats.len);
        defer booster.deinit();

        try booster.setParam("objective", "reg:squarederror");

        for (0..100) |i| {
            try booster.updateOneIter(@intCast(i), dtrain);
        }

        // predict
        const predicted_deltas = try booster.predict(dtest, 0, 0, 0);

        var predicted_weights = try allocator.alloc(f32, test_data.len);
        defer allocator.free(predicted_weights);

        var actual_weights = try allocator.alloc(f32, test_data.len);
        defer allocator.free(actual_weights);

        for (test_data, 0..) |record, i| {
            predicted_weights[i] = record.previous_weight + predicted_deltas[i];
            actual_weights[i] = record.weight;
        }

        const r2 = r2Score(actual_weights, predicted_weights);
        const mae = meanAbsoluteError(actual_weights, predicted_weights);
        const created_at = std.time.microTimestamp();

        const file_path = try std.fmt.allocPrintSentinel(
            allocator,
            "./models/model_{}_{}.ubj",
            .{ user_id, created_at },
            0,
        );
        defer allocator.free(file_path);

        const data_dir = std.fs.openDirAbsolute(absolute_path, .{}) catch blk: {
            std.fs.cwd().makeDir(absolute_path) catch return error.CouldntSaveModel;
            break :blk std.fs.openDirAbsolute(absolute_path, .{}) catch return error.CouldntSaveModel;
        };

        // XGBoost's saveModel requires the folder to already be created
        // if ./models cannot be opened, assume it is not present and create it
        _ = data_dir.openDir("./models", .{}) catch blk: {
            break :blk data_dir.makeDir("./models") catch return error.CouldntSaveModel;
        };
        booster.saveModel(file_path) catch return error.CouldntSaveModel;

        return .{
            .r2 = r2,
            .mae = mae,
            .created_at = created_at,
        };
    }
    fn trainTestSplit(
        data: []Features,
        test_size: f32,
    ) !struct { train: []const Features, @"test": []const Features } {
        const test_count = @as(u32, @intFromFloat(@round(test_size * @as(f32, @floatFromInt(data.len)))));
        const train_count = data.len - test_count;

        return .{
            .train = data[0..train_count],
            .@"test" = data[train_count..],
        };
    }
};

pub const Predict = struct {
    pub const Response = struct {
        predicted_delta: f32,
        predicted_weight: f32,
    };
    pub fn run(allocator: std.mem.Allocator, user_id: i32, data_dir: []const u8, data: []Data, windows: Windows) !Response {
        if (data.len < windows.long) {
            return error.NotEnoughData;
        }
        const file_name = getMostRecentModel(allocator, data_dir, user_id) catch return error.NoModelFound;
        defer allocator.free(file_name);

        const booster = XGBoost.Booster.initModelFromFile(file_name) catch return error.CouldntInitModel;
        defer booster.deinit();

        const long_window = data[data.len - windows.long ..];
        const short_window = data[data.len - windows.short ..];

        var calories_short: f32 = 0;
        var calories_long: f32 = 0;
        var carbs_long: f32 = 0;
        var sugar_long: f32 = 0;
        var protein_long: f32 = 0;
        var sodium_long: f32 = 0;

        for (long_window) |d| {
            calories_long += d.calories;
            carbs_long += d.carbs;
            sugar_long += d.sugar;
            protein_long += d.protein;
            sodium_long += d.sodium;
        }

        for (short_window) |d| {
            calories_short += d.calories;
        }

        const long_window_size = @as(f32, @floatFromInt(windows.long));
        const short_window_size = @as(f32, @floatFromInt(windows.short));
        const last_known_weight = data[data.len - 1].weight;

        const next_feature = Features{
            .calories_rolling_short = calories_short / short_window_size,
            .calories_rolling_long = calories_long / long_window_size,
            .carbs_rolling_long = carbs_long / long_window_size,
            .sugar_rolling_long = sugar_long / long_window_size,
            .protein_rolling_long = protein_long / long_window_size,
            .sodium_rolling_long = sodium_long / long_window_size,
            .previous_weight = last_known_weight,
            // 0 as they are the ones being predicted
            .weight_delta = 0,
            .weight = 0,
        };

        const feature_slice = [_]Features{next_feature};

        const dmat, const labels = try createMatrix(allocator, &feature_slice);
        defer {
            allocator.free(labels);
            dmat.deinit();
        }

        const predicted_deltas = try booster.predict(dmat, 0, 0, 0);

        if (predicted_deltas.len > 0) {
            const predicted_delta = predicted_deltas[0];
            const predicted_weight = last_known_weight + predicted_delta;

            return .{
                .predicted_weight = predicted_weight,
                .predicted_delta = predicted_delta,
            };
        } else {
            return error.PredictionFailed;
        }
    }
};

// utility functions
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

/// Caller owns memory
fn getMostRecentModel(allocator: std.mem.Allocator, data_dir: []const u8, user_id: i32) ![:0]u8 {
    const model_dir = try std.fmt.allocPrint(allocator, "{s}models", .{
        data_dir,
    });
    defer allocator.free(model_dir);

    const dir = try std.fs.openDirAbsolute(model_dir, .{ .iterate = true });
    var it = dir.iterate();

    var most_recent_model_date: ?i64 = null;
    while (try it.next()) |file| {
        var name_it = std.mem.tokenizeScalar(u8, file.name, '_');
        // the prefix should be "model"
        const prefix = name_it.next() orelse continue;
        if (!std.mem.eql(u8, prefix, "model")) continue;
        // the user id should match with the caller user id
        const user_id_str = name_it.next() orelse continue;
        const file_user_id = std.fmt.parseInt(i32, user_id_str, 10) catch continue;
        if (user_id != file_user_id) continue;
        const timestamp_str = blk: {
            const t = name_it.next() orelse continue;
            break :blk std.mem.trimEnd(u8, t, ".ubj");
        };
        const timestamp = std.fmt.parseInt(i64, timestamp_str, 10) catch continue;
        if (most_recent_model_date) |date| {
            if (timestamp > date) most_recent_model_date = timestamp;
        } else {
            most_recent_model_date = timestamp;
        }
    }
    if (most_recent_model_date == null) return error.CouldntFindModel;

    return try std.fmt.allocPrintSentinel(allocator, "{s}/model_{}_{}.ubj", .{
        model_dir,
        user_id,
        most_recent_model_date.?,
    }, 0);
}

fn meanAbsoluteError(actual: []const f32, predicted: []const f32) f32 {
    var sum_abs_error: f32 = 0;
    for (actual, 0..) |y_true, i| {
        sum_abs_error += @abs(y_true - predicted[i]);
    }
    return sum_abs_error / @as(f32, @floatFromInt(actual.len));
}

/// Caller is responsible for the matrix and the slice
fn createMatrix(allocator: std.mem.Allocator, data: []const Features) !struct { XGBoost.DMatrix, []f32 } {
    // subtract 1 because of weight and weight delta are not features
    const num_features = @typeInfo(Features).@"struct".fields.len - 2;

    var feat = try allocator.alloc(f32, data.len * num_features);
    defer allocator.free(feat);
    var labels = try allocator.alloc(f32, data.len);

    for (data, 0..) |record, i| {
        // WARN: if a new feature is added but not included here, it is UB
        feat[i * num_features + 0] = record.calories_rolling_long;
        feat[i * num_features + 1] = record.calories_rolling_short;
        feat[i * num_features + 2] = record.carbs_rolling_long;
        feat[i * num_features + 3] = record.sugar_rolling_long;
        feat[i * num_features + 4] = record.protein_rolling_long;
        feat[i * num_features + 5] = record.sodium_rolling_long;
        feat[i * num_features + 6] = record.previous_weight;
        labels[i] = record.weight_delta;
    }

    const dmat = try XGBoost.DMatrix.initFromMatrix(feat, data.len, num_features, -1, .{});
    try dmat.setFloatInfo("label", labels);

    return .{ dmat, labels };
}
const XGBoost = @import("xgboost");
const std = @import("std");

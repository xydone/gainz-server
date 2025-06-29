const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.measurements_model);

pub const MeasurementList = struct {
    list: []Measurement,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MeasurementList) void {
        self.allocator.free(self.list);
    }
};

pub const Measurement = struct {
    id: i32,
    created_at: i64,
    type: types.MeasurementType,
    value: f64,
};

pub fn create(user_id: i32, database: *pg.Pool, request: rq.PostMeasurement) anyerror!Measurement {
    var conn = try database.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.create, //
        .{
            user_id,
            request.type,
            request.value,
            request.date,
        }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    //NOTE: you must deinitialize rows or else query time balloons 10x
    defer row.?.deinit() catch {};
    const id = row.?.get(i32, 0);
    const created_at = row.?.get(i64, 1);
    const measurement_type = row.?.get(types.MeasurementType, 2);
    const value = row.?.get(f64, 3);

    return Measurement{ .id = id, .created_at = created_at, .type = measurement_type, .value = value };
}

pub fn get(user_id: i32, database: *pg.Pool, request: rq.GetMeasurement) anyerror!Measurement {
    var conn = try database.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.get, //
        .{ user_id, request.measurement_id }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;
    defer row.deinit() catch {};

    const id = row.get(i32, 0);
    const created_at = row.get(i64, 1);
    const measurement_type = row.get(types.MeasurementType, 2);
    const value = row.get(f64, 3);
    return Measurement{ .id = id, .created_at = created_at, .type = measurement_type, .value = value };
}

pub fn getRecent(user_id: i32, database: *pg.Pool, request: rq.GetMeasurementRecent) anyerror!Measurement {
    var conn = try database.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.getRecent, //
        .{ user_id, request.measurement_type }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse return error.NotFound;
    defer row.deinit() catch {};

    const id = row.get(i32, 0);
    const created_at = row.get(i64, 1);
    const measurement_type = row.get(types.MeasurementType, 2);
    const value = row.get(f64, 3);
    return Measurement{ .id = id, .created_at = created_at, .type = measurement_type, .value = value };
}

/// Returns MeasurementList, which must be deinitalized.
pub fn getInRange(user_id: i32, allocator: std.mem.Allocator, database: *pg.Pool, request: rq.GetMeasurementRange) anyerror!MeasurementList {
    var conn = try database.acquire();
    defer conn.release();
    var result = conn.query(SQL_STRINGS.getInRange, //
        .{ user_id, request.range_start, request.range_end, request.measurement_type }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(Measurement).init(allocator);

    while (try result.next()) |row| {
        const id = row.get(i32, 0);
        const created_at = row.get(i64, 1);
        const measurement_type = row.get(types.MeasurementType, 2);
        const value = row.get(f64, 3);
        try response.append(Measurement{ .id = id, .created_at = created_at, .type = measurement_type, .value = value });
    }
    if (response.items.len == 0) return error.NotFound;
    return MeasurementList{ .allocator = allocator, .list = try response.toOwnedSlice() };
}

pub fn delete(user_id: i32, database: *pg.Pool, request: rq.DeleteMeasurement) !i64 {
    var conn = try database.acquire();
    defer conn.release();
    return conn.exec(SQL_STRINGS.delete, //
        .{ user_id, request.measurement_id }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    } orelse error.NotFound;
}

const SQL_STRINGS = struct {
    pub const create = "INSERT INTO measurements (user_id,type, value, created_at) VALUES ($1,$2,$3,COALESCE(TO_TIMESTAMP($4, 'YYYY-MM-DD'), NOW())) RETURNING id,created_at, type, value;";
    pub const get = "SELECT id, created_at, type, value FROM measurements WHERE user_id = $1 AND id = $2";
    pub const getRecent = "SELECT id, created_at, type, value FROM measurements WHERE user_id = $1 AND type = $2 ORDER BY created_at DESC LIMIT 1;";
    pub const getInRange = "SELECT * FROM measurements WHERE user_id = $1 AND Date(created_at) >= $2 AND Date(created_at) <= $3 AND type = $4";
    pub const delete = "DELETE FROM measurements WHERE user_id = $1 AND id = $2;";
};

// TESTS
const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Measurement | Create (with date)" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const zdt = @import("zdt");
    const test_env = Tests.test_env;
    const test_name = "Measurement | Create (with date)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    const test_date = "2024-01-01";
    const provided_date = try zdt.Datetime.fromString(test_date, "%Y-%m-%d");
    const create_request = rq.PostMeasurement{
        .date = test_date,
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const response = create(setup.user.id, test_env.database, create_request) catch |err| {
            benchmark.fail(err);
            return err;
        };

        //validate date
        const db_timestamp = try zdt.Datetime.fromUnix(response.created_at, .microsecond, null);
        const db_date = try db_timestamp.floorTo(.day);
        const date_difference = provided_date.diff(db_date).asSeconds();

        std.testing.expectEqual(0, date_difference) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_request.value, response.value) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_request.type, response.type) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}
test "Measurement | Create (default date)" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const zdt = @import("zdt");
    const test_env = Tests.test_env;
    const test_name = "Measurement | Create (default date)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    const now_timestamp = try zdt.Datetime.now(null);
    const now_date = try now_timestamp.floorTo(.day);

    const create_request = rq.PostMeasurement{
        .date = null,
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const response = create(setup.user.id, test_env.database, create_request) catch |err| {
            benchmark.fail(err);
            return err;
        };

        //validate date
        const db_timestamp = try zdt.Datetime.fromUnix(response.created_at, .microsecond, null);
        const db_date = try db_timestamp.floorTo(.day);
        const date_difference = now_date.diff(db_date).asSeconds();

        std.testing.expectEqual(0, date_difference) catch |err| {
            benchmark.fail(err);
            return err;
        };

        std.testing.expectEqual(create_request.value, response.value) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(create_request.type, response.type) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "Measurement | Delete" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const test_name = "Measurement | Delete";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    const create_request = rq.PostMeasurement{
        .date = null,
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    // Initialize data
    const measurement = try create(setup.user.id, test_env.database, create_request);

    const created_measurements = [_]Measurement{measurement};
    // Test
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const amount_deleted = delete(setup.user.id, test_env.database, .{ .measurement_id = measurement.id }) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(@as(i64, @intCast(created_measurements.len)), amount_deleted) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "Measurement | Get in range (lower bound)" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    const test_name = "Measurement | Get in range (lower bound)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    var create_request = rq.PostMeasurement{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";
    const inserted_measurement = try create(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-03";
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-04";
    _ = try create(setup.user.id, test_env.database, create_request);

    const get_range_request = rq.GetMeasurementRange{
        .measurement_type = types.MeasurementType.neck,
        .range_start = "2025-01-02",
        .range_end = "2025-01-04",
    };

    // Only one measurement is expected to be in the range, as the others that follow
    // range_start <= date of insertion <= range_end
    // are for a different type (in our case, different than neck)
    const in_range_measurements = [_]Measurement{inserted_measurement};
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        var measurements = getInRange(setup.user.id, allocator, test_env.database, get_range_request) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer measurements.deinit();
        std.testing.expectEqual(in_range_measurements.len, measurements.list.len) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (measurements.list, in_range_measurements) |measurement, inserted| {
            std.testing.expectEqual(inserted.value, measurement.value) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted.type, measurement.type) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

test "Measurement | Get in range (upper bound)" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    const test_name = "Measurement | Get in range (upper bound)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    var create_request = rq.PostMeasurement{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";
    const inserted_measurement = try create(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-03";
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-04";
    _ = try create(setup.user.id, test_env.database, create_request);

    const get_range_request = rq.GetMeasurementRange{
        .measurement_type = types.MeasurementType.neck,
        .range_start = "2025-01-01",
        .range_end = "2025-01-02",
    };
    // Only one measurement is expected to be in the range, as the others that follow
    // range_start <= date of insertion <= range_end
    // are for a different type (in our case, different than neck)
    const in_range_measurements = [_]Measurement{inserted_measurement};

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        var measurements = getInRange(setup.user.id, allocator, test_env.database, get_range_request) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer measurements.deinit();

        std.testing.expectEqual(in_range_measurements.len, measurements.list.len) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (measurements.list, in_range_measurements) |measurement, inserted| {
            std.testing.expectEqual(inserted.value, measurement.value) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted.type, measurement.type) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

test "Measurement | Get in range (overlap)" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    const test_name = "Measurement | Get in range (overlap)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    var create_request = rq.PostMeasurement{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    const inserted_measurement = try create(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-03";
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-04";
    _ = try create(setup.user.id, test_env.database, create_request);

    const get_range_request = rq.GetMeasurementRange{
        .measurement_type = types.MeasurementType.weight,
        .range_start = "2025-01-02",
        .range_end = "2025-01-02",
    };
    // Only one measurement is expected to be in the range, as the others that follow
    // range_start <= date of insertion <= range_end
    // are for a different type (in our case, different than weight)
    const in_range_measurements = [_]Measurement{inserted_measurement};

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        var measurements = getInRange(setup.user.id, allocator, test_env.database, get_range_request) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer measurements.deinit();

        std.testing.expectEqual(in_range_measurements.len, measurements.list.len) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (measurements.list, in_range_measurements) |measurement, inserted| {
            std.testing.expectEqual(inserted.value, measurement.value) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted.type, measurement.type) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

test "Measurement | Get in range (multiple)" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    const test_name = "Measurement | Get in range (multiple)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    var create_request = rq.PostMeasurement{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    const measurement_1 = try create(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";
    const measurement_2 = try create(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-03";
    const measurement_3 = try create(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-04";
    const measurement_4 = try create(setup.user.id, test_env.database, create_request);

    const get_range_request = rq.GetMeasurementRange{
        .measurement_type = types.MeasurementType.weight,
        .range_start = "2025-01-01",
        .range_end = "2025-01-04",
    };
    const in_range_measurements = [_]Measurement{ measurement_1, measurement_2, measurement_3, measurement_4 };
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        var measurements = getInRange(setup.user.id, allocator, test_env.database, get_range_request) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer measurements.deinit();
        std.testing.expectEqual(in_range_measurements.len, measurements.list.len) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (measurements.list, in_range_measurements) |measurement, inserted| {
            std.testing.expectEqual(inserted.value, measurement.value) catch |err| {
                benchmark.fail(err);
                return err;
            };
            std.testing.expectEqual(inserted.type, measurement.type) catch |err| {
                benchmark.fail(err);
                return err;
            };
        }
    }
}

test "Measurement | Get in range (empty)" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    const test_name = "Measurement | Get in range (empty)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    var create_request = rq.PostMeasurement{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-03";
    _ = try create(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-04";
    _ = try create(setup.user.id, test_env.database, create_request);

    const get_range_request = rq.GetMeasurementRange{
        .measurement_type = types.MeasurementType.neck,
        .range_start = "2099-01-01",
        .range_end = "2099-01-01",
    };
    // TEST
    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    if (getInRange(setup.user.id, allocator, test_env.database, get_range_request)) |*measurement_list| {
        const list = @constCast(measurement_list);
        list.deinit();
    } else |err| {
        std.testing.expectEqual(error.NotFound, err) catch |inner_err| benchmark.fail(inner_err);
    }
}

test "Measurement | Get by ID" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const test_name = "Measurement | Get by ID";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    var create_request = rq.PostMeasurement{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };

    const measurement_1 = try create(setup.user.id, test_env.database, create_request);
    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";

    _ = try create(setup.user.id, test_env.database, create_request);
    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";

    _ = try create(setup.user.id, test_env.database, create_request);
    create_request.date = "2025-01-03";

    _ = try create(setup.user.id, test_env.database, create_request);
    create_request.date = "2025-01-04";

    _ = try create(setup.user.id, test_env.database, create_request);

    const get_measurement = rq.GetMeasurement{
        .measurement_id = @intCast(measurement_1.id),
    };
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const measurement = get(setup.user.id, test_env.database, get_measurement) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(measurement_1.id, measurement.id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(measurement_1.value, measurement.value) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(measurement_1.type, measurement.type) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "Measurement | Get recent" {
    // SETUP
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const test_name = "Measurement | Get recent";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit();

    var create_request = rq.PostMeasurement{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };

    _ = try create(setup.user.id, test_env.database, create_request);
    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";

    _ = try create(setup.user.id, test_env.database, create_request);
    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";

    _ = try create(setup.user.id, test_env.database, create_request);
    create_request.date = "2025-01-03";

    _ = try create(setup.user.id, test_env.database, create_request);
    create_request.date = "2025-01-04";

    const last_weight_measurement = try create(setup.user.id, test_env.database, create_request);

    const get_measurement = rq.GetMeasurementRecent{
        .measurement_type = .weight,
    };

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const measurement = getRecent(setup.user.id, test_env.database, get_measurement) catch |err| {
            benchmark.fail(err);
            return err;
        };

        std.testing.expectEqual(last_weight_measurement.id, measurement.id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(last_weight_measurement.value, measurement.value) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(last_weight_measurement.type, measurement.type) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

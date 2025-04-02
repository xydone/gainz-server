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
};

const SQL_STRINGS = struct {
    pub const create = "INSERT INTO measurements (user_id,type, value, created_at) VALUES ($1,$2,$3,COALESCE(TO_TIMESTAMP($4, 'YYYY-MM-DD'), NOW())) RETURNING id,created_at, type, value;";
    pub const get = "SELECT * FROM measurements WHERE user_id = $1 AND id = $2";
    pub const getInRange = "SELECT * FROM measurements WHERE user_id = $1 AND Date(created_at) >= $2 AND Date(created_at) <= $3 AND type = $4";
};

// TESTS
const Tests = @import("../tests/tests.zig");

test "create measurement with date" {
    const zdt = @import("zdt");
    const test_env = Tests.test_env;
    const create_request = rq.PostMeasurement{ .date = "2024-01-01", .type = types.MeasurementType.weight, .value = 75.35 };
    const response = try Measurement.create(1, test_env.database, create_request);

    //validate date
    const provided_date = try zdt.Datetime.fromString("2024-01-01", "%Y-%m-%d");
    const db_timestamp = try zdt.Datetime.fromUnix(response.created_at, .microsecond, null);
    const db_date = try db_timestamp.floorTo(.day);
    const date_difference = provided_date.diff(db_date).asSeconds();

    try std.testing.expectEqual(0, date_difference);
    try std.testing.expectEqual(create_request.value, response.value);
    try std.testing.expectEqual(create_request.type, response.type);
}
test "create measurement with defaulted date" {
    const zdt = @import("zdt");

    const test_env = Tests.test_env;
    const create_request = rq.PostMeasurement{ .date = null, .type = types.MeasurementType.weight, .value = 75.35 };
    const response = try Measurement.create(1, test_env.database, create_request);

    //validate date
    const db_timestamp = try zdt.Datetime.fromUnix(response.created_at, .microsecond, null);
    const db_date = try db_timestamp.floorTo(.day);
    const now_timestamp = try zdt.Datetime.now(null);
    const now_date = try now_timestamp.floorTo(.day);
    const date_difference = now_date.diff(db_date).asSeconds();

    try std.testing.expectEqual(create_request.value, response.value);
    try std.testing.expectEqual(create_request.type, response.type);
    try std.testing.expectEqual(0, date_difference);
}

test "create multiple measurements tests:noTime" {
    const test_env = Tests.test_env;
    var create_request = rq.PostMeasurement{ .date = "2025-01-01", .type = types.MeasurementType.weight, .value = 75.35 };
    _ = try Measurement.create(1, test_env.database, create_request);
    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";
    _ = try Measurement.create(1, test_env.database, create_request);
    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";
    _ = try Measurement.create(1, test_env.database, create_request);
    create_request.date = "2025-01-03";
    _ = try Measurement.create(1, test_env.database, create_request);
    create_request.date = "2025-01-04";
    _ = try Measurement.create(1, test_env.database, create_request);
}

test "get measurements in range - lower bound" {
    const test_env = Tests.test_env;
    const get_range_request = rq.GetMeasurementRange{
        .measurement_type = types.MeasurementType.neck,
        .range_start = "2025-01-02",
        .range_end = "2025-01-04",
    };

    var measurements = try Measurement.getInRange(1, test_env.allocator, test_env.database, get_range_request);
    defer measurements.deinit();
    try std.testing.expectEqual(1, measurements.list.len);
}

test "get measurements in range - upper bound" {
    const test_env = Tests.test_env;
    const get_range_request = rq.GetMeasurementRange{
        .measurement_type = types.MeasurementType.neck,
        .range_start = "2025-01-01",
        .range_end = "2025-01-02",
    };

    var measurements = try Measurement.getInRange(1, test_env.allocator, test_env.database, get_range_request);
    defer measurements.deinit();
    try std.testing.expectEqual(1, measurements.list.len);
}

test "get measurements in range - overlap" {
    const test_env = Tests.test_env;
    const get_range_request = rq.GetMeasurementRange{
        .measurement_type = types.MeasurementType.neck,
        .range_start = "2025-01-02",
        .range_end = "2025-01-02",
    };

    var measurements = try Measurement.getInRange(1, test_env.allocator, test_env.database, get_range_request);
    defer measurements.deinit();
    try std.testing.expectEqual(1, measurements.list.len);
}

test "get measurements in range - count" {
    const test_env = Tests.test_env;
    const get_range_request = rq.GetMeasurementRange{
        .measurement_type = types.MeasurementType.weight,
        .range_start = "2025-01-01",
        .range_end = "2025-01-04",
    };

    var measurements = try Measurement.getInRange(1, test_env.allocator, test_env.database, get_range_request);
    defer measurements.deinit();
    try std.testing.expectEqual(4, measurements.list.len);
}

test "get measurements in range - no response" {
    const test_env = Tests.test_env;
    const get_range_request = rq.GetMeasurementRange{
        .measurement_type = types.MeasurementType.neck,
        .range_start = "2099-01-01",
        .range_end = "2099-01-01",
    };

    var measurements = Measurement.getInRange(1, test_env.allocator, test_env.database, get_range_request) catch |err| {
        return try std.testing.expect(err == error.NotFound);
    };
    defer measurements.deinit();
}

test "get measurement by id" {
    const test_env = Tests.test_env;
    const get_measurement = rq.GetMeasurement{
        .measurement_id = 1,
    };

    const measurement = try Measurement.get(1, test_env.database, get_measurement);
    try std.testing.expectEqual(1, measurement.id);
}

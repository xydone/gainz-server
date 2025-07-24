const std = @import("std");

const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;

const Handler = @import("../handler.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.measurements_model);

pub const Create = struct {
    pub const Request = struct {
        type: types.MeasurementType,
        value: f64,
        date: ?[]const u8 = null,
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        type: types.MeasurementType,
        value: f64,
    };
    pub const Errors = error{
        CannotCreate,
        CannotParseResult,
    } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var row = conn.row(query_string, //
            .{
                user_id,
                request.type,
                request.value,
                request.date,
            }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);

            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer row.deinit() catch {};

        return row.to(Response, .{ .dupe = true }) catch return error.CannotCreate;
    }
    const query_string = "INSERT INTO measurements (user_id,type, value, created_at) VALUES ($1,$2,$3,COALESCE(TO_TIMESTAMP($4, 'YYYY-MM-DD'), NOW())) RETURNING id,created_at, type, value;";
};

pub const Get = struct {
    pub const Response = struct {
        id: i32,
        created_at: i64,
        type: types.MeasurementType,
        value: f64,
    };
    pub const Errors = error{
        CannotGet,
        NotFound,
        CannotParseResult,
    } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, measurement_id: u32) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var row = conn.row(query_string, //
            .{ user_id, measurement_id }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);

            return error.CannotGet;
        } orelse return error.NotFound;
        defer row.deinit() catch {};

        return row.to(Response, .{}) catch return error.CannotParseResult;
    }
    const query_string = "SELECT id, created_at, type, value FROM measurements WHERE user_id = $1 AND id = $2";
};

pub const GetRecent = struct {
    pub const Response = struct {
        id: i32,
        created_at: i64,
        type: types.MeasurementType,
        value: f64,
    };
    pub const Errors = error{
        CannotGet,
        NotFound,
        CannotParseResult,
    } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, measurement_type: types.MeasurementType) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var row = conn.row(query_string, //
            .{ user_id, measurement_type }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);

            return error.CannotGet;
        } orelse return error.NotFound;
        defer row.deinit() catch {};

        return row.to(Response, .{}) catch return error.CannotParseResult;
    }
    const query_string = "SELECT id, created_at, type, value FROM measurements WHERE user_id = $1 AND type = $2 ORDER BY created_at DESC LIMIT 1;";
};

pub const GetInRange = struct {
    pub const Request = struct {
        /// datetime string (ex: 2024-01-01)
        range_start: []const u8,
        /// datetime string (ex: 2024-01-01)
        range_end: []const u8,
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        type: types.MeasurementType,
        value: f64,
    };
    pub const Errors = error{
        CannotGet,
        NotFound,
        CannotParseResult,
        OutOfMemory,
    } || DatabaseErrors;
    pub fn call(user_id: i32, allocator: std.mem.Allocator, database: *Pool, measurement_type: types.MeasurementType, request: Request) Errors![]Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var result = conn.query(query_string, //
            .{ user_id, request.range_start, request.range_end, measurement_type }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);

            return error.CannotGet;
        };
        defer result.deinit();
        var response = std.ArrayList(Response).init(allocator);

        while (result.next() catch return error.CannotGet) |row| {
            try response.append(row.to(Response, .{}) catch return error.CannotParseResult);
        }
        if (response.items.len == 0) return error.NotFound;
        return response.toOwnedSlice() catch return error.OutOfMemory;
    }
    const query_string = "SELECT * FROM measurements WHERE user_id = $1 AND Date(created_at) >= $2 AND Date(created_at) <= $3 AND type = $4";
};

pub const Delete = struct {
    pub const Response = i64;
    pub const Errors = error{
        CannotDelete,
        NotFound,
        CannotParseResult,
    } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, measurement_id: i32) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        return conn.exec(query_string, .{ user_id, measurement_id }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);

            return error.CannotDelete;
        } orelse error.NotFound;
    }
    const query_string = "DELETE FROM measurements WHERE user_id = $1 AND id = $2";
};

// TESTS
const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "API Measurement | Create (with date)" {
    // SETUP
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const zdt = @import("zdt");
    const test_env = Tests.test_env;
    const test_name = "API Measurements | Create (with date)";
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const test_date = "2024-01-01";
    const provided_date = try zdt.Datetime.fromString(test_date, "%Y-%m-%d");
    const create_request = Create.Request{
        .date = test_date,
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const response = Create.call(setup.user.id, test_env.database, create_request) catch |err| {
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
test "API Measurement | Create (default date)" {
    // SETUP
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const zdt = @import("zdt");
    const test_env = Tests.test_env;
    const test_name = "API Measurements | Create (default date)";
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const now_timestamp = try zdt.Datetime.now(null);
    const now_date = try now_timestamp.floorTo(.day);

    const create_request = Create.Request{
        .date = null,
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const response = Create.call(setup.user.id, test_env.database, create_request) catch |err| {
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

test "API Measurement | Delete" {
    // SETUP
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const test_env = Tests.test_env;
    const test_name = "API Measurements | Delete";
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const create_request = Create.Request{
        .date = null,
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    // Initialize data
    const measurement = try Create.call(setup.user.id, test_env.database, create_request);

    const created_measurements = [_]Create.Response{measurement};
    // Test
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const amount_deleted = Delete.call(setup.user.id, test_env.database, measurement.id) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqual(@as(i64, @intCast(created_measurements.len)), amount_deleted) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

test "API Measurement | Get in range (lower bound)" {
    // SETUP
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;
    const test_env = Tests.test_env;
    const test_name = "API Measurements | Get in range (lower bound)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    var create_request = Create.Request{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";
    const inserted_measurement = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-03";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-04";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    const get_range_request = GetInRange.Request{
        .range_start = "2025-01-02",
        .range_end = "2025-01-04",
    };

    // Only one measurement is expected to be in the range, as the others that follow
    // range_start <= date of insertion <= range_end
    // are for a different type (in our case, different than neck)
    const in_range_measurements = [_]Create.Response{inserted_measurement};
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const measurements = GetInRange.call(
            setup.user.id,
            allocator,
            test_env.database,
            types.MeasurementType.neck,
            get_range_request,
        ) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer allocator.free(measurements);

        std.testing.expectEqual(in_range_measurements.len, measurements.len) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (measurements, in_range_measurements) |measurement, inserted| {
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

test "API Measurement | Get in range (upper bound)" {
    // SETUP
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    const test_name = "API Measurements | Get in range (upper bound)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    var create_request = Create.Request{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";
    const inserted_measurement = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-03";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-04";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    const get_range_request = GetInRange.Request{
        .range_start = "2025-01-01",
        .range_end = "2025-01-02",
    };
    // Only one measurement is expected to be in the range, as the others that follow
    // range_start <= date of insertion <= range_end
    // are for a different type (in our case, different than neck)
    const in_range_measurements = [_]Create.Response{inserted_measurement};

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const measurements = GetInRange.call(setup.user.id, allocator, test_env.database, types.MeasurementType.neck, get_range_request) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer allocator.free(measurements);

        std.testing.expectEqual(in_range_measurements.len, measurements.len) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (measurements, in_range_measurements) |measurement, inserted| {
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

test "API Measurement | Get in range (overlap)" {
    // SETUP
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    const test_name = "API Measurements | Get in range (overlap)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    var create_request = Create.Request{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    const inserted_measurement = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-03";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-04";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    const get_range_request = GetInRange.Request{
        .range_start = "2025-01-02",
        .range_end = "2025-01-02",
    };
    // Only one measurement is expected to be in the range, as the others that follow
    // range_start <= date of insertion <= range_end
    // are for a different type (in our case, different than weight)
    const in_range_measurements = [_]Create.Response{inserted_measurement};

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const measurements = GetInRange.call(
            setup.user.id,
            allocator,
            test_env.database,
            types.MeasurementType.weight,
            get_range_request,
        ) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer allocator.free(measurements);

        std.testing.expectEqual(in_range_measurements.len, measurements.len) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (measurements, in_range_measurements) |measurement, inserted| {
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

test "API Measurement | Get in range (multiple)" {
    // SETUP
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    const test_name = "API Measurements | Get in range (multiple)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    var create_request = Create.Request{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    const measurement_1 = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";
    const measurement_2 = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-03";
    const measurement_3 = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-04";
    const measurement_4 = try Create.call(setup.user.id, test_env.database, create_request);

    const get_range_request = GetInRange.Request{
        .range_start = "2025-01-01",
        .range_end = "2025-01-04",
    };
    const in_range_measurements = [_]Create.Response{ measurement_1, measurement_2, measurement_3, measurement_4 };
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const measurements = GetInRange.call(
            setup.user.id,
            allocator,
            test_env.database,
            types.MeasurementType.weight,
            get_range_request,
        ) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer allocator.free(measurements);

        std.testing.expectEqual(in_range_measurements.len, measurements.len) catch |err| {
            benchmark.fail(err);
            return err;
        };
        for (measurements, in_range_measurements) |measurement, inserted| {
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

test "API Measurement | Get in range (empty)" {
    // SETUP
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;
    const test_name = "API Measurements | Get in range (empty)";
    var setup = try TestSetup.init(test_env.database, test_name);
    defer setup.deinit(allocator);

    var create_request = Create.Request{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-03";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    create_request.date = "2025-01-04";
    _ = try Create.call(setup.user.id, test_env.database, create_request);

    const get_range_request = GetInRange.Request{
        .range_start = "2099-01-01",
        .range_end = "2099-01-01",
    };
    // TEST
    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    if (GetInRange.call(
        setup.user.id,
        allocator,
        test_env.database,
        types.MeasurementType.neck,
        get_range_request,
    )) |*measurement_list| {
        const list = @constCast(measurement_list);
        allocator.free(list.*);
    } else |err| {
        std.testing.expectEqual(error.NotFound, err) catch |inner_err| benchmark.fail(inner_err);
    }
}

test "API Measurement | Get by ID" {
    // SETUP
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const test_env = Tests.test_env;
    const test_name = "API Measurements | Get by ID";
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    var create_request = Create.Request{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };

    const measurement_1 = try Create.call(setup.user.id, test_env.database, create_request);
    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";

    _ = try Create.call(setup.user.id, test_env.database, create_request);
    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";

    _ = try Create.call(setup.user.id, test_env.database, create_request);
    create_request.date = "2025-01-03";

    _ = try Create.call(setup.user.id, test_env.database, create_request);
    create_request.date = "2025-01-04";

    _ = try Create.call(setup.user.id, test_env.database, create_request);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const measurement = Get.call(setup.user.id, test_env.database, @intCast(measurement_1.id)) catch |err| {
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

test "API Measurement | Get recent" {
    // SETUP
    const Benchmark = @import("../tests/test_runner.zig").Benchmark;
    const test_env = Tests.test_env;
    const test_name = "API Measurements | Get recent";
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    var create_request = Create.Request{
        .date = "2025-01-01",
        .type = types.MeasurementType.weight,
        .value = 75.35,
    };

    _ = try Create.call(setup.user.id, test_env.database, create_request);
    create_request.type = types.MeasurementType.neck;
    create_request.date = "2025-01-02";

    _ = try Create.call(setup.user.id, test_env.database, create_request);
    create_request.type = types.MeasurementType.weight;
    create_request.date = "2025-01-02";

    _ = try Create.call(setup.user.id, test_env.database, create_request);
    create_request.date = "2025-01-03";

    _ = try Create.call(setup.user.id, test_env.database, create_request);
    create_request.date = "2025-01-04";

    const last_weight_measurement = try Create.call(setup.user.id, test_env.database, create_request);

    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();

        const measurement = GetRecent.call(
            setup.user.id,
            test_env.database,
            .weight,
        ) catch |err| {
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

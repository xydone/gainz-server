const std = @import("std");

const pg = @import("pg");

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.measurements_model);

pub fn create(ctx: *Handler.RequestContext, request: rq.PostMeasurement) anyerror!rs.PostMeasurement {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.create, //
        .{ ctx.user_id, request.type, request.value }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    //NOTE: you must deinitialize rows or else query time balloons 10x
    defer row.?.deinit() catch {};
    const created_at = row.?.get(i64, 0);
    const measurement_type = row.?.get(types.MeasurementType, 1);
    const value = row.?.get(f64, 2);

    return rs.PostMeasurement{ .created_at = created_at, .type = measurement_type, .value = value };
}

pub fn get(ctx: *Handler.RequestContext, request: rq.GetMeasurement) anyerror!rs.GetMeasurement {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var row = conn.row(SQL_STRINGS.get, //
        .{ ctx.user_id.?, request.measurement_id }) catch |err| {
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
    return rs.GetMeasurement{ .id = id, .created_at = created_at, .measurement_type = measurement_type, .value = value };
}

pub fn getInRange(ctx: *Handler.RequestContext, request: rq.GetMeasurementRange) anyerror![]rs.GetMeasurement {
    var conn = try ctx.app.db.acquire();
    defer conn.release();
    var result = conn.query(SQL_STRINGS.getInRange, //
        .{ ctx.user_id.?, request.range_start, request.range_end, request.measurement_type }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(rs.GetMeasurement).init(ctx.app.allocator);

    while (try result.next()) |row| {
        const id = row.get(i32, 0);
        const created_at = row.get(i64, 1);
        const measurement_type = row.get(types.MeasurementType, 2);
        const value = row.get(f64, 3);
        try response.append(rs.GetMeasurement{ .id = id, .created_at = created_at, .measurement_type = measurement_type, .value = value });
    }
    return try response.toOwnedSlice();
}

pub const SQL_STRINGS = struct {
    pub const create = "insert into measurements (user_id,type, value) values ($1,$2,$3) returning created_at, type, value;";
    pub const get = "SELECT * FROM measurements WHERE user_id = $1 AND id = $2";
    pub const getInRange = "SELECT * FROM measurements WHERE user_id = $1 AND created_at >= $2 AND created_at < $3 AND type = $4";
};

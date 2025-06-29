const std = @import("std");

const pg = @import("pg");

const Handler = @import("../../handler.zig");
const rq = @import("../../request.zig");

const log = std.log.scoped(.unit_model);

pub fn create(ctx: *Handler.RequestContext, request: rq.PostUnit) anyerror!void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    _ = try conn.exec(SQL_STRINGS.createUnit, .{ ctx.user_id, request.amount, request.unit, request.multiplier });
}

const SQL_STRINGS = struct {
    pub const createUnit =
        \\INSERT INTO
        \\exercise_unit (created_by, amount, unit, multiplier)
        \\VALUES
        \\($1, $2, $3, $4)
    ;
};

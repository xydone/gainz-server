const std = @import("std");

const pg = @import("pg");

const Handler = @import("../../handler.zig");
const rq = @import("../../request.zig");
const rs = @import("../../response.zig");

const log = std.log.scoped(.category_model);

pub fn create(ctx: *Handler.RequestContext, request: rq.PostCategory) anyerror!void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    _ = try conn.exec(SQL_STRINGS.createCategory, .{ ctx.user_id, request.name, request.description });
}
pub fn get(ctx: *Handler.RequestContext) anyerror![]rs.GetCategories {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var result = conn.queryOpts(SQL_STRINGS.getCategories, .{ctx.user_id}, .{ .column_names = true }) catch |err| {
        if (conn.err) |pg_err| {
            log.err("severity: {s} |code: {s} | failure: {s}", .{ pg_err.severity, pg_err.code, pg_err.message });
        }
        return err;
    };
    defer result.deinit();
    var response = std.ArrayList(rs.GetCategories).init(ctx.app.allocator);
    while (try result.next()) |row| {
        const id = row.get(i32, 0);

        const name = row.getCol([]u8, "name");
        const description = row.getCol(?[]u8, "description");

        try response.append(rs.GetCategories{
            .id = id,
            .name = try ctx.app.allocator.dupe(u8, name),
            .description = if (description == null) null else try ctx.app.allocator.dupe(u8, description.?),
        });
    }
    return try response.toOwnedSlice();
}

const SQL_STRINGS = struct {
    pub const createCategory =
        \\INSERT INTO
        \\exercise_category (created_by, name, description)
        \\VALUES
        \\($1, $2, $3)
    ;
    pub const getCategories = "SELECT id,name, description FROM exercise_category WHERE created_by = $1";
};

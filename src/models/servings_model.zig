const std = @import("std");

const Pool = @import("../db.zig").Pool;
const DatabaseErrors = @import("../db.zig").DatabaseErrors;
const ErrorHandler = @import("../db.zig").ErrorHandler;

const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const auth = @import("../util/auth.zig");

const log = std.log.scoped(.servings_model);

pub const Create = struct {
    pub const Request = struct {
        food_id: i32,
        amount: f64,
        unit: []const u8,
        multiplier: f64,
    };
    pub const Response = struct {
        id: i32,
        amount: f64,
        unit: []u8,
        multiplier: f64,
        food_id: i32,

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            allocator.free(self.unit);
        }
    };
    pub const Errors = error{
        CannotCreate,
        OutOfMemory,
    } || DatabaseErrors;
    pub fn call(ctx: *Handler.RequestContext, request: Request) Errors!Response {
        var conn = ctx.app.db.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var result = conn.rowOpts(query_string, .{ ctx.user_id, request.food_id, request.amount, request.unit, request.multiplier }, .{}) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;

        const id = result.get(i32, 0);
        const amount = result.get(f64, 1);
        const unit = result.get([]u8, 2);
        const multiplier = result.get(f64, 3);
        const food_id = result.get(i32, 4);

        return Response{
            .id = id,
            .amount = amount,
            .unit = ctx.app.allocator.dupe(u8, unit) catch return error.OutOfMemory,
            .multiplier = multiplier,
            .food_id = food_id,
        };
    }
    const query_string = "INSERT INTO servings (created_by, food_id, amount, unit, multiplier) VALUES($1,$2,$3,$4,$5) RETURNING id, amount, unit, multiplier, food_id;";
};

pub const Get = struct {
    pub const Request = struct {
        food_id: i32,
    };
    pub const Response = struct {
        id: i32,
        amount: f64,
        unit: []const u8,
        multiplier: f64,

        pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
            allocator.free(self.unit);
        }
    };
    pub const Errors = error{
        CannotGet,
        InvalidFoodID,
        OutOfMemory,
    } || DatabaseErrors;
    // Caller must free list
    pub fn call(ctx: *Handler.RequestContext, request: Request) Errors![]Response {
        var conn = ctx.app.db.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();
        var result = conn.queryOpts(query_string, //
            .{request.food_id}, .{ .column_names = true }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        };
        defer result.deinit();
        var response = std.ArrayList(Response).init(ctx.app.allocator);

        while (result.next() catch return error.CannotGet) |row| {
            const id = row.get(i32, 0);
            const amount = row.get(f64, 3);
            const unit = row.get([]u8, 4);
            const multiplier = row.get(f64, 5);

            response.append(Response{ .id = id, .amount = amount, .unit = unit, .multiplier = multiplier }) catch return error.OutOfMemory;
        }
        if (response.items.len == 0) return error.InvalidFoodID;
        return response.toOwnedSlice() catch return error.OutOfMemory;
    }
    const query_string = "SELECT * from servings WHERE food_id=$1";
};

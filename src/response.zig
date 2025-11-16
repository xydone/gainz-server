pub const ResponseError = struct {
    code: u16,
    message: []const u8,
    details: ?[]const u8 = null,

    // 400
    pub const bad_request: ResponseError = .{
        .code = 400,
        .message = "Bad request.",
    };
    pub const body_missing: ResponseError = .{
        .code = 400,
        .message = "The request body is not found.",
    };
    pub const body_missing_fields: ResponseError = .{
        .code = 400,
        .message = "The request body is missing required fields.",
    };
    pub const unauthorized: ResponseError = .{
        .code = 401,
        .message = "You are not authorized to make this request.",
    };

    pub const not_found: ResponseError = .{
        .code = 404,
        .message = "Not found.",
    };

    // 500
    pub const internal_server_error: ResponseError = .{
        .code = 500,
        .message = "An unexpected error occurred on the server. Please try again later.",
    };
};

pub fn handleResponse(httpz_res: *httpz.Response, response_error: ResponseError, details: ?[]const u8) void {
    var response = response_error;
    response.details = details orelse null;
    httpz_res.status = response.code;
    httpz_res.json(response, .{ .emit_null_optional_fields = false }) catch @panic("Couldn't parse error response.");
    return;
}

const std = @import("std");

const types = @import("types.zig");
const httpz = @import("httpz");

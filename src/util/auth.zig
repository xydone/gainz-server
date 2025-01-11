const std = @import("std");

const jwt = @import("jwt");

pub const JWTClaims = struct {
    user_id: i32,
    exp: i64,
};

pub fn verifyPassword(allocator: std.mem.Allocator, hash: []const u8, password: []const u8) !bool {
    const verify_error = std.crypto.pwhash.argon2.strVerify(
        hash,
        password,
        .{ .allocator = allocator },
    );

    return if (verify_error)
        true
    else |err| switch (err) {
        error.AuthenticationFailed, error.PasswordVerificationFailed => false,
        else => err,
    };
}

pub fn hashPassword(allocator: std.mem.Allocator, password: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, 128);
    return try std.crypto.pwhash.argon2.strHash(
        password,
        .{
            .allocator = allocator,
            .params = .{ .t = 3, .m = 32, .p = 4 },
        },
        buf,
    );
}

pub fn createJWT(allocator: std.mem.Allocator, claims: anytype, secret: []const u8) ![]const u8 {
    return try jwt.encode(
        allocator,
        .{ .alg = .HS256 },
        claims,
        .{ .secret = secret },
    );
}

pub fn createSessionToken(allocator: std.mem.Allocator) ![]const u8 {
    //NOTE: is this actually secure?
    var buf: [128]u8 = undefined;
    std.crypto.random.bytes(&buf);
    var dest: [172]u8 = undefined;
    const temp = std.base64.Base64Encoder.init(std.base64.standard_alphabet_chars, '=').encode(&dest, &buf);

    return allocator.dupe(u8, temp);
}

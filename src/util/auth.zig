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

// https://github.com/thienpow/zui/blob/467c84de15259956a2139bba4a863ac0285a8a22/src/app/utils/password.zig#L37-L64
pub fn hashPassword(allocator: std.mem.Allocator, password: []const u8) ![]const u8 {
    // Argon2id output format: $argon2id$v=19$m=32,t=3,p=4$salt$hash
    // Typical max length: ~108 bytes with default salt (16 bytes) and hash (32 bytes)
    // Using 128 as a safe upper bound
    const buf_size = 128;
    const buf = try allocator.alloc(u8, buf_size);

    const hashed = try std.crypto.pwhash.argon2.strHash(
        password,
        .{
            .allocator = allocator,
            .params = .{
                .t = 1, // Time cost
                .m = 32, // Memory cost (32 KiB)
                .p = 4, // Parallelism
            },
            .mode = .argon2id, // Explicitly specify for consistency
        },
        buf,
    );

    // Trim the buffer to actual size
    const actual_len = hashed.len;
    if (actual_len < buf_size) {
        return try allocator.realloc(buf, actual_len);
    }
    return hashed;
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

pub fn jsonStringify(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    const fmt = std.json.fmt(value, .{});

    var writer = std.Io.Writer.Allocating.init(allocator);
    try fmt.format(&writer.writer);

    return writer.toOwnedSlice();
}

const std = @import("std");

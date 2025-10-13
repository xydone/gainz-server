const Errors = error{
    CantReadFile,
    ParseZon,
    ExpectedUnion,
};
pub fn readZon(T: type, allocator: Allocator, path: []const u8, max_bytes: u32) Errors!T {
    const file = std.fs.cwd().readFileAllocOptions(
        allocator,
        path,
        max_bytes,
        null,
        std.mem.Alignment.@"8",
        0,
    ) catch return error.CantReadFile;
    defer allocator.free(file);

    var diagnostics: zon.parse.Diagnostics = .{};
    defer diagnostics.deinit(allocator);

    return zon.parse.fromSlice(T, allocator, file, &diagnostics, .{}) catch {
        var error_it = diagnostics.iterateErrors();
        while (error_it.next()) |status_err| {
            if (std.mem.eql(u8, "expected union", status_err.type_check.message)) return error.ExpectedUnion;
        }
        return error.ParseZon;
    };
}

const zon = std.zon;
const Allocator = std.mem.Allocator;
const std = @import("std");

// https://github.com/zigster64/dotenv.zig/
const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// const Self = @This();

pub const dotenv = struct {
    map: std.process.EnvMap = undefined,
    pub fn init(allocator: Allocator, filename: ?[]const u8) !dotenv {
        var map = try std.process.getEnvMap(allocator);

        if (filename) |f| {
            var file = std.fs.cwd().openFile(f, .{}) catch {
                return .{ .map = map };
            };

            defer file.close();
            var buf: [1024]u8 = undefined;
            var reader = file.reader(&buf);

            while (reader.interface.takeDelimiterExclusive('\n')) |line| {
                // ignore commented out lines
                if (line.len > 0 and line[0] == '#') {
                    continue;
                }
                // split into KEY and Value
                if (std.mem.indexOf(u8, line, "=")) |index| {
                    const key = line[0..index];
                    const value = line[index + 1 ..];
                    try map.put(key, value);
                }
            } else |err| switch (err) {
                error.EndOfStream => {}, // normal termination if the file does not end with a line which contains a new line
                else => return err,
            }
        }
        return .{
            .map = map,
        };
    }

    pub fn deinit(self: *dotenv) void {
        self.map.deinit();
    }

    pub fn get(self: dotenv, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }

    pub fn put(self: *dotenv, key: []const u8, value: []const u8) !void {
        return self.map.put(key, value);
    }
};

// test "load an env file" {
//     var basic_env = try Self.init(testing.allocator, null);
//     defer basic_env.deinit();
//     const basic_env_count = basic_env.map.count();

//     var expanded_env = try Self.init(testing.allocator, ".env");
//     defer expanded_env.deinit();
//     const expanded_env_count = expanded_env.map.count();

//     try testing.expectEqual(basic_env_count + 3, expanded_env_count);
//     try testing.expectEqualStrings("1", expanded_env.get("VALUE1").?);
//     try testing.expectEqualStrings("2", expanded_env.get("VALUE2").?);
//     try testing.expectEqualStrings("3", expanded_env.get("VALUE3").?);
//     try testing.expectEqual(null, expanded_env.get("VALUE4"));
// }

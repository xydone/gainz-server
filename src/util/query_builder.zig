const std = @import("std");

pub const QueryBuildError = error{
    MismatchedParameters, // If total_parameters is not divisible by params_per_entry
    ZeroParametersPerEntry, // If params_per_entry is 0
};

pub const Datatype = struct {
    index: usize,
    type_string: []const u8,
};

pub const Query = struct {
    allocator: std.mem.Allocator,
    prefix: []const u8,
    suffix: []const u8,
    /// Will be deallocated by `.deinit()`
    root: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, prefix: ?[]const u8, suffix: ?[]const u8) Query {
        return Query{
            .allocator = allocator,
            .prefix = prefix orelse "",
            .suffix = suffix orelse "",
        };
    }

    pub fn deinit(self: Query) void {
        self.allocator.free(self.root.?);
    }

    /// Caller must free memory.
    pub fn build(self: *Query, start_index: u64, total_parameters: u64, params_per_entry: u64) !void {
        if (params_per_entry == 0) {
            if (total_parameters == 0) {
                return;
            }
            return QueryBuildError.ZeroParametersPerEntry;
        }

        if (total_parameters == 0) {
            return;
        }

        if (total_parameters % params_per_entry != 0) {
            std.debug.print("MISMATCHED! total: {} params per entry: {}\n", .{ total_parameters, params_per_entry });
            return QueryBuildError.MismatchedParameters;
        }

        const number_of_entries = total_parameters / params_per_entry;

        var allocating_writer = std.Io.Writer.Allocating.init(self.allocator);
        errdefer allocating_writer.deinit();

        var current_placeholder_idx = start_index;

        for (0..number_of_entries) |entry_idx| {
            if (entry_idx != 0) {
                try allocating_writer.writer.writeAll(",");
            }

            try allocating_writer.writer.writeAll("(");

            for (0..params_per_entry) |param_idx_in_entry| {
                if (param_idx_in_entry != 0) {
                    try allocating_writer.writer.writeAll(",");
                }

                try allocating_writer.writer.print("${}", .{current_placeholder_idx});
                current_placeholder_idx += 1;
            }
            try allocating_writer.writer.writeAll(")");
        }

        self.*.root = try allocating_writer.toOwnedSlice();
    }

    /// Caller owns memory
    pub fn getJoined(self: Query) ![]u8 {
        return try std.mem.join(self.allocator, "", &[_][]const u8{ self.prefix, self.root.?, self.suffix });
    }
};

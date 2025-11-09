const log = std.log.scoped(.exercise_model);

pub const Create = struct {
    pub const Request = struct {
        name: []const u8,
        description: ?[]const u8 = null,
        category_ids: []i32,
        unit_ids: []i32,
    };
    pub const Response = struct {
        id: i32,
        created_by: i32,
        name: []const u8,
        description: ?[]const u8,
    };
    pub const Errors = error{ CannotCreate, CannotParseResult } || DatabaseErrors;

    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var row = conn.row(query_string, //
            .{ user_id, request.name, request.description, request.unit_ids, request.category_ids }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotCreate;
        } orelse return error.CannotCreate;
        defer row.deinit() catch {};

        return row.to(Response, .{}) catch return error.CannotParseResult;
    }
    const query_string =
        \\WITH
        \\inserted_exercise AS (
        \\INSERT INTO training.exercise (created_by, name, description)
        \\VALUES ($1, $2, $3)
        \\RETURNING id, created_by, name, description
        \\),
        \\inserted_unit AS (
        \\INSERT INTO training.exercise_has_unit (exercise_id, unit_id)
        \\SELECT e.id, u.unit_id
        \\FROM inserted_exercise e
        \\CROSS JOIN UNNEST($4::int[]) AS u(unit_id)
        \\),
        \\inserted_category AS (
        \\INSERT INTO training.exercise_has_category (exercise_id, category_id)
        \\SELECT e.id, c.category_id
        \\FROM inserted_exercise e
        \\CROSS JOIN UNNEST($5::int[]) AS c(category_id)
        \\)
        \\SELECT e.*
        \\FROM inserted_exercise e;
    ;
};

pub const GetAll = struct {
    pub const Request = struct {};
    pub const Response = struct {
        list: []Exercise,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Response) void {
            self.allocator.free(self.list);
        }
    };

    const Exercise = struct {
        id: i32,
        name: []const u8,
        description: ?[]const u8,
    };
    pub const Errors = error{
        CannotGet,
        CannotParseResult,
        OutOfMemory,
    } || DatabaseErrors;

    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var result = conn.queryOpts(query_string, .{user_id}, .{ .column_names = true }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        };
        defer result.deinit();
        var response: std.ArrayList(Exercise) = .empty;
        while (result.next() catch return error.CannotGet) |row| {
            const id = row.get(i32, 0);

            const name = row.getCol([]u8, "name");
            const description = row.getCol(?[]u8, "description");

            response.append(allocator, Exercise{
                .id = id,
                .name = allocator.dupe(u8, name) catch return error.OutOfMemory,
                .description = if (description == null) null else allocator.dupe(u8, description.?) catch return error.OutOfMemory,
            }) catch return error.OutOfMemory;
        }
        return Response{ .list = response.toOwnedSlice(allocator) catch return error.OutOfMemory, .allocator = allocator };
    }
    const query_string = "SELECT id,name, description FROM training.exercise WHERE created_by = $1";
};

pub const GetRange = struct {
    pub const Request = struct {
        /// datetime string (ex: 2024-01-01)
        range_start: []const u8,
        /// datetime string (ex: 2024-01-01)
        range_end: []const u8,
    };
    pub const Response = struct {
        list: []EntryList,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Response) void {
            self.allocator.free(self.list);
        }
    };

    //TODO: this is super ugly.
    pub const EntryList = struct {
        entry_id: i32,
        entry_created_at: i64,
        created_by: i32,
        exercise_id: i32,
        exercise_name: []const u8,
        exercise_description: ?[]const u8,
        value: f64,
        unit_id: i32,
        unit_name: []const u8,
        unit_amount: f64,
        unit_multiplier: f64,
        notes: ?[]const u8,
        category_id: i32,
        category_name: []const u8,
        category_description: ?[]const u8,
    };
    pub const Errors = error{
        CannotGet,
        CannotParseResult,
        OutOfMemory,
        NoEntriesFound,
    } || DatabaseErrors;

    pub fn call(allocator: std.mem.Allocator, user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var result = conn.queryOpts(query_string, .{ user_id, request.range_start, request.range_end }, .{}) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotGet;
        };
        defer result.deinit();
        var response: std.ArrayList(EntryList) = .empty;
        while (result.next() catch return error.CannotGet) |row| {
            response.append(allocator, row.to(EntryList, .{ .dupe = true }) catch return error.OutOfMemory) catch return error.OutOfMemory;
        }
        if (response.items.len == 0) {
            response.deinit(allocator);
            return error.NoEntriesFound;
        }
        return Response{ .list = response.toOwnedSlice(allocator) catch return error.OutOfMemory, .allocator = allocator };
    }
    const query_string =
        \\ SELECT 
        \\ee.id AS entry_id,
        \\ee.created_at AS entry_created_at,
        \\ee.created_by,
        \\ee.exercise_id,
        \\ex.name AS exercise_name,
        \\ex.description AS exercise_description,
        \\ee.value,
        \\ee.unit_id,
        \\eu.unit AS unit_name,
        \\eu.amount AS unit_amount,
        \\eu.multiplier AS unit_multiplier,
        \\ee.notes,
        \\ec.id AS category_id,
        \\ec.name AS category_name,
        \\ec.description AS category_description
        \\FROM 
        \\training.exercise_entry ee
        \\JOIN 
        \\training.exercise ex ON ee.exercise_id = ex.id
        \\JOIN 
        \\training.exercise_unit eu ON ee.unit_id = eu.id
        \\JOIN 
        \\training.exercise_has_category ehc ON ee.exercise_id = ehc.exercise_id
        \\JOIN 
        \\training.exercise_category ec ON ehc.category_id = ec.id
        \\WHERE 
        \\ee.created_by = $1
        \\AND DATE (ee.created_at) >= $2
        \\AND DATE (ee.created_at) <= $3
    ;
};

pub const LogExercise = struct {
    pub const Request = struct {
        exercise_id: u32,
        unit_id: u32,
        value: f32,
        notes: ?[]const u8 = null,
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        created_by: i32,
        exercise_id: i32,
        value: f64,
        unit_id: i32,
        notes: ?[]const u8,
    };
    pub const Errors = error{
        CannotLog,
        CannotParseResult,
    } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var row = conn.row(query_string, .{ user_id, request.exercise_id, request.value, request.unit_id, request.notes }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotLog;
        } orelse return error.CannotLog;
        defer row.deinit() catch {};

        return row.to(Response, .{}) catch return error.CannotParseResult;
    }
    const query_string =
        \\INSERT INTO
        \\training.exercise_entry (created_by, exercise_id, value, unit_id, notes)
        \\VALUES
        \\($1, $2, $3, $4, $5)
        \\RETURNING *
    ;
};

pub const DeleteExerciseEntry = struct {
    pub const Request = struct {};
    pub const Response = struct {
        id: i32,
        created_at: i64,
        created_by: i32,
        exercise_id: i32,
        value: f64,
        unit_id: i32,
        notes: ?[]const u8,
    };
    pub const Errors = error{
        CannotDelete,
        CannotParseResult,
    } || DatabaseErrors;
    pub fn call(user_id: i32, database: *Pool, entry_id: u32) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var row = conn.row(query_string, .{ user_id, entry_id }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotDelete;
        } orelse return error.CannotDelete;
        defer row.deinit() catch {};

        return row.to(Response, .{}) catch return error.CannotParseResult;
    }
    const query_string =
        \\DELETE FROM training.exercise_entry
        \\WHERE created_by = $1
        \\AND id = $2
        \\RETURNING *;
    ;
};

pub const EditExerciseEntry = struct {
    pub const Request = struct {
        exercise_id: ?i32 = null,
        value: ?f64 = null,
        unit_id: ?i32 = null,
        notes: ?[]const u8 = null,

        pub fn isValid(self: Request) bool {
            return self.exercise_id != null or self.value != null or self.unit_id != null or self.notes != null;
        }
    };
    pub const Response = struct {
        id: i32,
        created_at: i64,
        created_by: i32,
        exercise_id: i32,
        value: f64,
        unit_id: i32,
        notes: ?[]const u8,
    };
    pub const Errors = error{
        CannotEdit,
        CannotParseResult,
    } || DatabaseErrors;
    pub fn call(user_id: i32, entry_id: u32, database: *Pool, request: Request) Errors!Response {
        var conn = database.acquire() catch return error.CannotAcquireConnection;
        defer conn.release();

        var row = conn.row(query_string, .{ user_id, entry_id, request.exercise_id, request.value, request.unit_id, request.notes }) catch |err| {
            const error_handler = ErrorHandler{ .conn = conn };
            const error_data = error_handler.handle(err);
            if (error_data) |data| ErrorHandler.printErr(data);
            return error.CannotEdit;
        } orelse return error.CannotEdit;
        defer row.deinit() catch {};

        return row.to(Response, .{ .dupe = true }) catch return error.CannotParseResult;
    }
    const query_string =
        \\UPDATE training.exercise_entry
        \\SET
        \\exercise_id = COALESCE($3, exercise_id),
        \\value = COALESCE($4, value),
        \\unit_id = COALESCE($5, unit_id),
        \\notes = COALESCE($6, notes)
        \\WHERE created_by = $1
        \\AND id = $2
        \\RETURNING *;
    ;
};

const Tests = @import("../../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "API Exercise | Create" {
    const test_name = "API Exercise | Create";
    //SETUP
    const CreateCategory = @import("category.zig").Create;
    const CreateUnit = @import("unit.zig").Create;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const category = try CreateCategory.call(setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    const unit = try CreateUnit.call(setup.user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    // TEST
    {
        const request = Create.Request{
            .name = test_name,
            .category_ids = &category_ids,
            .unit_ids = &unit_ids,
        };
        const response = try Create.call(setup.user.id, test_env.database, request);

        try std.testing.expectEqual(request.description, response.description);
        try std.testing.expectEqualStrings(request.name, response.name);
    }
}

test "API Exercise | Log Entry" {
    const test_name = "API Exercise | Log Entry";
    //SETUP
    const CreateCategory = @import("category.zig").Create;
    const CreateUnit = @import("unit.zig").Create;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const category = try CreateCategory.call(setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    const unit = try CreateUnit.call(setup.user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    const create_request = Create.Request{
        .name = test_name,
        .category_ids = &category_ids,
        .unit_ids = &unit_ids,
    };
    const create_response = try Create.call(setup.user.id, test_env.database, create_request);

    // TEST
    {
        const request = LogExercise.Request{
            .exercise_id = @intCast(create_response.id),
            .unit_id = @intCast(unit.id),
            .value = 15,
        };
        const response = try LogExercise.call(setup.user.id, test_env.database, request);

        try std.testing.expectEqual(@as(i32, @intCast(request.exercise_id)), response.exercise_id);
        try std.testing.expectEqual(@as(i32, @intCast(request.unit_id)), response.unit_id);
        try std.testing.expectEqual(request.value, response.value);
        if (request.notes) |notes| {
            try std.testing.expectEqualStrings(notes, response.notes.?);
        }
    }
}

test "API Exercise | Edit Entry" {
    const test_name = "API Exercise | Edit Entry";
    //SETUP
    const CreateCategory = @import("category.zig").Create;
    const CreateUnit = @import("unit.zig").Create;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const category = try CreateCategory.call(setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    const unit = try CreateUnit.call(setup.user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    const create_request = Create.Request{
        .name = test_name,
        .category_ids = &category_ids,
        .unit_ids = &unit_ids,
    };
    const create_response = try Create.call(setup.user.id, test_env.database, create_request);

    const log_request = LogExercise.Request{
        .exercise_id = @intCast(create_response.id),
        .unit_id = @intCast(unit.id),
        .value = 15,
    };
    const log_response = try LogExercise.call(setup.user.id, test_env.database, log_request);

    const unit_request = CreateUnit.Request{
        .amount = 10,
        .multiplier = 1,
        .unit = test_name ++ "'s unit",
    };
    const unit_response = try CreateUnit.call(setup.user.id, test_env.database, unit_request);

    // TEST
    {
        const request = EditExerciseEntry.Request{
            .value = 10,
            .unit_id = unit_response.id,
        };
        const response = try EditExerciseEntry.call(setup.user.id, @intCast(log_response.id), test_env.database, request);

        try std.testing.expectEqual(@as(i32, @intCast(log_request.exercise_id)), response.exercise_id);
        try std.testing.expectEqual(@as(i32, @intCast(request.unit_id.?)), response.unit_id);
        try std.testing.expectEqual(request.value, response.value);
        if (log_request.notes) |notes| {
            try std.testing.expectEqualStrings(notes, response.notes.?);
        }
    }
}

test "API Exercise | Delete Entry" {
    const test_name = "API Exercise | Delete Entry";
    //SETUP
    const CreateCategory = @import("category.zig").Create;
    const CreateUnit = @import("unit.zig").Create;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const category = try CreateCategory.call(setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    const unit = try CreateUnit.call(setup.user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    const create_request = Create.Request{
        .name = test_name,
        .category_ids = &category_ids,
        .unit_ids = &unit_ids,
    };
    const create_response = try Create.call(setup.user.id, test_env.database, create_request);

    const log_request = LogExercise.Request{
        .exercise_id = @intCast(create_response.id),
        .unit_id = @intCast(unit.id),
        .value = 15,
    };
    const log_response = try LogExercise.call(setup.user.id, test_env.database, log_request);
    // TEST
    {
        const response = try DeleteExerciseEntry.call(setup.user.id, test_env.database, @intCast(log_response.id));

        try std.testing.expectEqual(@as(i32, @intCast(log_request.exercise_id)), response.exercise_id);
        try std.testing.expectEqual(@as(i32, @intCast(log_request.unit_id)), response.unit_id);
        try std.testing.expectEqual(log_request.value, response.value);
        if (log_request.notes) |notes| {
            try std.testing.expectEqualStrings(notes, response.notes.?);
        }
    }
}

test "API Exercise | Get Range" {
    const zdt = @import("zdt");
    const test_name = "API Exercise | Get Range";
    //SETUP
    const CreateCategory = @import("category.zig").Create;
    const CreateUnit = @import("unit.zig").Create;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const category = try CreateCategory.call(setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    const unit = try CreateUnit.call(setup.user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    const create_request = Create.Request{
        .name = test_name,
        .category_ids = &category_ids,
        .unit_ids = &unit_ids,
    };
    const create_response = try Create.call(setup.user.id, test_env.database, create_request);

    const log_request_1 = LogExercise.Request{
        .exercise_id = @intCast(create_response.id),
        .unit_id = @intCast(unit.id),
        .value = 15,
    };

    const log_request_2 = LogExercise.Request{
        .exercise_id = @intCast(create_response.id),
        .unit_id = @intCast(unit.id),
        .value = 8,
    };
    const log_response_1 = try LogExercise.call(setup.user.id, test_env.database, log_request_1);
    const log_response_2 = try LogExercise.call(setup.user.id, test_env.database, log_request_2);

    const logged_responses = [_]LogExercise.Response{ log_response_1, log_response_2 };

    // setup dates
    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .week));

    var lower_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.toString("%Y-%m-%d", &lower_bound_string.writer);
    try upper_bound.toString("%Y-%m-%d", &upper_bound_string.writer);

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    // TEST
    {
        const request = GetRange.Request{
            .range_start = range_start,
            .range_end = range_end,
        };
        var response = try GetRange.call(allocator, setup.user.id, test_env.database, request);
        defer response.deinit();

        try std.testing.expectEqual(logged_responses.len, response.list.len);
        for (response.list, logged_responses) |entry, logged| {
            try std.testing.expectEqual(logged.id, entry.entry_id);
            try std.testing.expectEqual(logged.exercise_id, entry.exercise_id);
            try std.testing.expectEqual(logged.unit_id, entry.unit_id);
            try std.testing.expectEqual(logged.value, entry.value);
            if (logged.notes) |logged_notes| {
                if (entry.notes) |entry_notes| {
                    try std.testing.expectEqualStrings(logged_notes, entry_notes);
                } else {
                    // notes missing in entry when they were in response
                    const err = error.NotesMissing;
                    return err;
                }
            }
        }
    }
}
test "API Exercise | Get Range Upper Bound" {
    const zdt = @import("zdt");
    const test_name = "API Exercise | Get Range Upper Bound";
    //SETUP
    const CreateCategory = @import("category.zig").Create;
    const CreateUnit = @import("unit.zig").Create;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const category = try CreateCategory.call(setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    const unit = try CreateUnit.call(setup.user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    const create_request = Create.Request{
        .name = test_name,
        .category_ids = &category_ids,
        .unit_ids = &unit_ids,
    };
    const create_response = try Create.call(setup.user.id, test_env.database, create_request);

    const log_request_1 = LogExercise.Request{
        .exercise_id = @intCast(create_response.id),
        .unit_id = @intCast(unit.id),
        .value = 15,
    };

    const log_request_2 = LogExercise.Request{
        .exercise_id = @intCast(create_response.id),
        .unit_id = @intCast(unit.id),
        .value = 8,
    };
    const log_response_1 = try LogExercise.call(setup.user.id, test_env.database, log_request_1);
    const log_response_2 = try LogExercise.call(setup.user.id, test_env.database, log_request_2);

    const logged_responses = [_]LogExercise.Response{ log_response_1, log_response_2 };

    // setup dates
    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);
    var lower_bound = try now_day.sub(zdt.Duration.fromTimespanMultiple(1, .week));
    var upper_bound = now_day;

    var lower_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.toString("%Y-%m-%d", &lower_bound_string.writer);
    try upper_bound.toString("%Y-%m-%d", &upper_bound_string.writer);

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    // TEST
    {
        const request = GetRange.Request{
            .range_start = range_start,
            .range_end = range_end,
        };
        var response = try GetRange.call(allocator, setup.user.id, test_env.database, request);
        defer response.deinit();

        try std.testing.expectEqual(logged_responses.len, response.list.len);
        for (response.list, logged_responses) |entry, logged| {
            try std.testing.expectEqual(logged.id, entry.entry_id);
            try std.testing.expectEqual(logged.exercise_id, entry.exercise_id);
            try std.testing.expectEqual(logged.unit_id, entry.unit_id);
            try std.testing.expectEqual(logged.value, entry.value);
            if (logged.notes) |logged_notes| {
                if (entry.notes) |entry_notes| {
                    try std.testing.expectEqualStrings(logged_notes, entry_notes);
                } else {
                    // notes missing in entry when they were in response
                    const err = error.NotesMissing;
                    return err;
                }
            }
        }
    }
}

test "API Exercise | Get Range Lower Bound" {
    const zdt = @import("zdt");
    const test_name = "API Exercise | Get Range Lower Bound";
    //SETUP
    const CreateCategory = @import("category.zig").Create;
    const CreateUnit = @import("unit.zig").Create;
    const test_env = Tests.test_env;
    var setup = try TestSetup.init(test_env.database, test_name);
    const allocator = std.testing.allocator;
    defer setup.deinit(allocator);

    const category = try CreateCategory.call(setup.user.id, test_env.database, .{
        .name = "Chest",
    });
    const unit = try CreateUnit.call(setup.user.id, test_env.database, .{
        .amount = 1,
        .unit = "kg",
        .multiplier = 1,
    });

    var unit_ids = [_]i32{unit.id};
    var category_ids = [_]i32{category.id};
    const create_request = Create.Request{
        .name = test_name,
        .category_ids = &category_ids,
        .unit_ids = &unit_ids,
    };
    const create_response = try Create.call(setup.user.id, test_env.database, create_request);

    const log_request_1 = LogExercise.Request{
        .exercise_id = @intCast(create_response.id),
        .unit_id = @intCast(unit.id),
        .value = 15,
    };

    const log_request_2 = LogExercise.Request{
        .exercise_id = @intCast(create_response.id),
        .unit_id = @intCast(unit.id),
        .value = 8,
    };
    const log_response_1 = try LogExercise.call(setup.user.id, test_env.database, log_request_1);
    const log_response_2 = try LogExercise.call(setup.user.id, test_env.database, log_request_2);

    const logged_responses = [_]LogExercise.Response{ log_response_1, log_response_2 };

    // setup dates
    const now = try zdt.Datetime.now(null);
    const now_day = try now.floorTo(.day);

    var lower_bound = now_day;
    var upper_bound = try now_day.add(zdt.Duration.fromTimespanMultiple(1, .week));
    var lower_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer lower_bound_string.deinit();
    var upper_bound_string: std.Io.Writer.Allocating = .init(allocator);
    defer upper_bound_string.deinit();

    try lower_bound.toString("%Y-%m-%d", &lower_bound_string.writer);
    try upper_bound.toString("%Y-%m-%d", &upper_bound_string.writer);

    const range_start = try lower_bound_string.toOwnedSlice();
    defer allocator.free(range_start);
    const range_end = try upper_bound_string.toOwnedSlice();
    defer allocator.free(range_end);

    // TEST
    {
        const request = GetRange.Request{
            .range_start = range_start,
            .range_end = range_end,
        };
        var response = try GetRange.call(allocator, setup.user.id, test_env.database, request);
        defer response.deinit();

        try std.testing.expectEqual(logged_responses.len, response.list.len);
        for (response.list, logged_responses) |entry, logged| {
            try std.testing.expectEqual(logged.id, entry.entry_id);
            try std.testing.expectEqual(logged.exercise_id, entry.exercise_id);
            try std.testing.expectEqual(logged.unit_id, entry.unit_id);
            try std.testing.expectEqual(logged.value, entry.value);
            if (logged.notes) |logged_notes| {
                if (entry.notes) |entry_notes| {
                    try std.testing.expectEqualStrings(logged_notes, entry_notes);
                } else {
                    // notes missing in entry when they were in response
                    const err = error.NotesMissing;
                    return err;
                }
            }
        }
    }
}

const std = @import("std");

const Pool = @import("../../db.zig").Pool;
const DatabaseErrors = @import("../../db.zig").DatabaseErrors;
const ErrorHandler = @import("../../db.zig").ErrorHandler;

const Handler = @import("../../handler.zig");

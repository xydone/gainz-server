const std = @import("std");

const httpz = @import("httpz");

const Create = @import("../models/users_model.zig").Create;
const Handler = @import("../handler.zig");
const rq = @import("../request.zig");
const rs = @import("../response.zig");
const types = @import("../types.zig");
const Measurement = @import("./measurement.zig");
const NoteEntries = @import("note_entries.zig");
const Goals = @import("goals.zig");
const Entry = @import("entry.zig");

const log = std.log.scoped(.users);

pub inline fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    router.*.post("/api/user", createUser, .{});

    //subroutes
    // /api/user/entry
    Entry.init(router);
    // /api/user/measurement
    Measurement.init(router);
    // /api/user/notes
    NoteEntries.init(router);
    // /api/user/goals
    Goals.init(router);
}

pub fn createUser(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) anyerror!void {
    const allocator = ctx.app.allocator;
    const body = req.body() orelse {
        try rs.handleResponse(res, rs.ResponseError.body_missing, null);
        return;
    };
    const json = std.json.parseFromSliceLeaky(Create.Request, allocator, body, .{}) catch {
        try rs.handleResponse(res, rs.ResponseError.not_found, null);
        return;
    };
    const response = Create.call(ctx.app.db, allocator, json) catch {
        try rs.handleResponse(res, rs.ResponseError.internal_server_error, null);
        return;
    };
    defer response.deinit(allocator);

    res.status = 200;
    try res.json(response, .{});
}

const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Endpoint User | Create" {
    // SETUP
    const test_name = "Endpoint User | Create";
    const ht = @import("httpz").testing;
    const Benchmark = @import("../tests/benchmark.zig");
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    const body = Create.Request{
        .username = test_name,
        .display_name = "Display " ++ test_name,
        .password = "Testing password",
    };
    const body_string = try std.json.stringifyAlloc(allocator, body, .{});
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(null, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var benchmark = Benchmark.start(test_name);
        defer benchmark.end();
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        createUser(&context, web_test.req, web_test.res) catch |err| {
            benchmark.fail(err);
            return err;
        };
        web_test.expectStatus(200) catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response_body = web_test.getBody() catch |err| {
            benchmark.fail(err);
            return err;
        };
        const response = std.json.parseFromSlice(Create.Response, allocator, response_body, .{}) catch |err| {
            benchmark.fail(err);
            return err;
        };
        defer response.deinit();

        std.testing.expectEqualStrings(body.username, response.value.username) catch |err| {
            benchmark.fail(err);
            return err;
        };
        std.testing.expectEqualStrings(body.display_name, response.value.display_name) catch |err| {
            benchmark.fail(err);
            return err;
        };
    }
}

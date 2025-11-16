const log = std.log.scoped(.users);
pub const endpoint_data = [_]EndpointData{
    CreateEndpoint.endpoint_data,
};

pub inline fn init(router: *Handler.Router) void {
    CreateEndpoint.init(router);

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

const CreateEndpoint = Endpoint(struct {
    pub const endpoint_data: EndpointData = .{
        .Request = .{
            .Body = CreateModel.Request,
        },
        .Response = CreateModel.Response,
        .method = .POST,
        .config = .{},
        .path = "/api/user",
        .route_data = .{},
    };
    pub fn call(ctx: *Handler.RequestContext, request: EndpointRequest(CreateModel.Request, void, void), res: *httpz.Response) anyerror!void {
        const allocator = ctx.app.allocator;

        const response = CreateModel.call(ctx.app.db, allocator, request.body) catch |err| {
            switch (err) {
                CreateModel.Errors.UsernameNotUnique => {
                    handleResponse(res, ResponseError.unauthorized, "Username already exists");
                },
                else => {
                    handleResponse(res, ResponseError.internal_server_error, null);
                },
            }
            return;
        };
        defer response.deinit(allocator);

        res.status = 200;
        try res.json(response, .{});
    }
});
const Tests = @import("../tests/tests.zig");
const TestSetup = Tests.TestSetup;

test "Endpoint User | Create" {
    // SETUP
    const test_name = "Endpoint User | Create";
    const ht = @import("httpz").testing;
    const test_env = Tests.test_env;
    const allocator = std.testing.allocator;

    const body = CreateModel.Request{
        .username = test_name,
        .display_name = "Display " ++ test_name,
        .password = "Testing password",
    };
    const body_string = try jsonStringify(allocator, body);
    defer allocator.free(body_string);

    var context = try TestSetup.createContext(null, allocator, test_env.database);
    defer TestSetup.deinitContext(allocator, context);
    // TEST
    {
        var web_test = ht.init(.{});
        defer web_test.deinit();

        web_test.body(body_string);

        try CreateEndpoint.call(&context, web_test.req, web_test.res);
        try web_test.expectStatus(200);
        const response_body = try web_test.getBody();
        const response = try std.json.parseFromSlice(CreateModel.Response, allocator, response_body, .{});
        defer response.deinit();

        try std.testing.expectEqualStrings(body.username, response.value.username);
        try std.testing.expectEqualStrings(body.display_name, response.value.display_name);
    }
}

const std = @import("std");

const httpz = @import("httpz");

const CreateModel = @import("../models/users_model.zig").Create;
const Handler = @import("../handler.zig");
const handleResponse = @import("../response.zig").handleResponse;
const ResponseError = @import("../response.zig").ResponseError;
const jsonStringify = @import("../util/jsonStringify.zig").jsonStringify;

const types = @import("../types.zig");
const Measurement = @import("./measurement.zig");
const NoteEntries = @import("note_entries.zig");
const Goals = @import("goals.zig");
const Entry = @import("entry.zig");

const Endpoint = @import("../endpoint.zig").Endpoint;
const EndpointRequest = @import("../endpoint.zig").EndpointRequest;
const EndpointData = @import("../endpoint.zig").EndpointData;

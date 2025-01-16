const std = @import("std");

const httpz = @import("httpz");

const Handler = @import("../handler.zig");

const log = std.log.scoped(.public);

pub fn init(router: *httpz.Router(*Handler, *const fn (*Handler.RequestContext, *httpz.request.Request, *httpz.response.Response) anyerror!void)) void {
    router.*.get("/*", dynamicPublicRoutes, .{});
}

fn dynamicPublicRoutes(ctx: *Handler.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = ctx; // autofix
    const file_path = if (std.mem.eql(u8, req.url.raw, "/")) "index.html" else req.url.raw[1..];
    const file_ext = std.fs.path.extension(file_path);

    //check if the requested file is permitted
    const content_type = checkFileExtension(file_ext) catch {
        res.status = 400;
        res.body = "Bad request";
        return;
    };

    const dir = try std.fs.cwd().openDir("src/public/", .{});
    const file = try dir.openFile(file_path, .{});

    //TODO: why 1024? is it good enough?
    var buf: [1024]u8 = undefined;
    var fifo = std.fifo.LinearFifo(u8, .Slice).init(&buf);
    try fifo.pump(file.reader(), res.writer());
    res.content_type = content_type;
    return;
}

fn checkFileExtension(file_ext: []const u8) !httpz.ContentType {
    if (std.mem.eql(u8, file_ext, ".html")) {
        return httpz.ContentType.HTML;
    } else if (std.mem.eql(u8, file_ext, ".css")) {
        return httpz.ContentType.CSS;
    } else if (std.mem.eql(u8, file_ext, ".js")) {
        return httpz.ContentType.JS;
    } else if (std.mem.eql(u8, file_ext, ".ico")) {
        return httpz.ContentType.ICO;
    } else return error.BadFileExtension;
}

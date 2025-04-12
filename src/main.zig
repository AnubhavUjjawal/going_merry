const std = @import("std");
const xev = @import("xev");

pub const std_options: std.Options = .{
    .log_level = .info,
};

const log = std.log.scoped(.main);

// TODO: Handle interrupts
// https://github.com/wooster0/soft/blob/786b45fff5f0a5c9106a907b5036a2041906fdb7/examples/backends/terminal/src/main.zig#L234

pub fn main() !void {
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    const address = try std.net.Address.parseIp("127.0.0.1", 8080);

    const u = try xev.UDP.init(address);
    try u.bind(address);

    var c: xev.Completion = undefined;
    defer u.close(&loop, &c, void, null, closeCallback);

    var rc: xev.Completion = undefined;

    // Max size of UDP packet is 65,535
    var buffer: [65_536]u8 = undefined;
    const rb: xev.ReadBuffer = .{ .slice = buffer[0..] };

    // not sure if this will work. Seems platform dependent.
    var state: xev.UDP.State = undefined;
    u.read(&loop, &rc, &state, rb, void, null, readCallback);
    // 5s timer
    // w.run(&loop, &c, 5000, void, null, &timerCallback);
    log.info("init everything", .{});
    try loop.run(.until_done);
}

fn readCallback(
    userdata: ?*void,
    loop: *xev.Loop,
    c: *xev.Completion,
    s: *xev.UDP.State,
    addr: std.net.Address,
    se: xev.UDP,
    b: xev.ReadBuffer,
    r: xev.ReadError!usize,
) xev.CallbackAction {
    _ = userdata;
    _ = loop;
    _ = se;

    log.info("completion: {any} {any} {any} {any}", .{ c.result, c.flags, s, addr });
    const read_bytes = r catch |err| blk: {
        log.warn("error when reading {!}", .{err});
        break :blk 0;
    };

    switch (b) {
        .slice => |v| {
            log.info("recieved data size {d} {s}", .{ read_bytes, v[0..read_bytes] });
        },
        else => unreachable,
    }
    return .rearm;
}

fn closeCallback(
    userdata: ?*void,
    loop: *xev.Loop,
    c: *xev.Completion,
    s: xev.UDP,
    result: xev.CloseError!void,
) xev.CallbackAction {
    _ = userdata;
    _ = loop;
    _ = c;
    _ = s;
    _ = result catch unreachable;
    log.warn("shutting down server", .{});
    return .disarm;
}

test {
    std.testing.log_level = .debug;
    _ = @import("bencode.zig");
    _ = @import("metainfo.zig");
    _ = @import("tracker/factory.zig");
}

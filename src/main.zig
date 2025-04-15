const std = @import("std");
const xev = @import("xev");
const signals = @import("signals.zig");
const tracker_interface = @import("tracker/interface.zig");
const tracker_factory = @import("tracker/factory.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

const log = std.log.scoped(.main);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    try signals.setSignalHandlers();
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    const tracker_address = try std.net.Address.parseIp4("127.0.0.1", 3000);
    const self_address = try std.net.Address.parseIp4("127.0.0.1", 8080);

    var client_factory = tracker_factory.ClientFactory.init(allocator);
    defer client_factory.deinit();

    const client = try client_factory.get(
        tracker_factory.ClientFactory.Type.udp,
        self_address,
        tracker_address,
        tracker_factory.logAnnounceCb,
        &loop,
    );

    var announce_request: tracker_interface.Client.AnnounceRequest = .{
        .info_hash = "abcded",
        .uploaded = 0,
        .downloaded = 0,
        .left = 100,
        .event = .none,
        .peer = .{ .ip = "127.0.0.1", .port = 2116, .peer_id = "abcdef" },
    };
    try client.announce(&announce_request);
    // const u = try xev.UDP.init(address);
    // try u.bind(address);

    // var rc: xev.Completion = undefined;
    // // Max size of UDP packet is 65,535
    // var buffer: [65_536]u8 = undefined;
    // const rb: xev.ReadBuffer = .{ .slice = buffer[0..] };

    // // not sure if this will work. Seems platform dependent.
    // var state: xev.UDP.State = undefined;
    // u.read(&loop, &rc, &state, rb, void, null, &readCallback);
    // // 5s timer
    // // w.run(&loop, &c, 5000, void, null, &timerCallback);
    // log.info("init everything", .{});

    // var tc: xev.Completion = undefined;
    // var t = try xev.Timer.init();
    // defer t.deinit();
    // t.run(&loop, &tc, 100, xev.Timer, &t, &timerCallback);

    try loop.run(.once);
}

fn timerCallback(
    userdata: ?*xev.Timer,
    loop: *xev.Loop,
    tc: *xev.Completion,
    _: xev.Timer.RunError!void,
) xev.CallbackAction {
    if (@atomicLoad(bool, &signals.shutdown_initiated, .unordered)) {
        loop.stop();
        return .disarm;
    }

    var timer = userdata.?;
    timer.run(loop, tc, 100, xev.Timer, timer, &timerCallback);
    return .disarm;
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
    if (@atomicLoad(bool, &signals.shutdown_initiated, .unordered)) {
        return .disarm;
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
    _ = @import("signals.zig");
}

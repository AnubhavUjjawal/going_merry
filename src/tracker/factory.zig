const std = @import("std");
const xev = @import("xev");
const interface = @import("interface.zig");
const udp = @import("udp.zig");

const log = std.log.scoped(.tracker);

pub const ClientFactory = struct {
    pub const Type = enum {
        udp,
        http,
    };
    const Errors = error{ InvalidTrackerType, OutOfMemory };
    const Self = @This();

    /// To keep track of allocated memory. useful in deinit calls.
    _udp_trackers: std.ArrayList(*udp.Client),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        const udp_trackers = std.ArrayList(*udp.Client).init(allocator);
        return .{
            .allocator = allocator,
            ._udp_trackers = udp_trackers,
        };
    }

    pub fn deinit(self: *Self) void {
        defer self._udp_trackers.deinit();
        for (self._udp_trackers.items) |item| {
            self.allocator.destroy(item);
        }
    }

    pub fn get(
        self: *Self,
        typ: Type,
        self_address: std.net.Address,
        tracker_address: std.net.Address,
        callback: interface.Client.AnnounceFunctionCallback,
        /// NOTE: Currently we do not support other event queue implementations,
        /// in the future however, we would like to support something like libuv.
        event_loop: *xev.Loop,
    ) Errors!interface.Client {
        switch (typ) {
            .udp => {
                var instance = try self.allocator.create(udp.Client);
                try self._udp_trackers.append(instance);

                var udp_client = udp.Client.init(self_address, tracker_address, callback, event_loop, self.allocator);
                instance = &udp_client;
                return instance.adapt();
            },
            else => {
                log.warn("tracker type {any} not implemented", .{typ});
                return Errors.InvalidTrackerType;
            },
        }
    }
};

/// to be only used for factory testing purposes
pub fn logAnnounceCb(data: *interface.Client.AnnounceResponse) anyerror!void {
    log.info("got data back {any}", .{data});
}

test {
    _ = @import("interface.zig");
    _ = @import("udp.zig");
}

test "return error on unimplemented tracker types" {
    const allocator = std.testing.allocator;
    var factory = ClientFactory.init(allocator);
    var loop: xev.Loop = undefined;

    const self_address = try std.net.Address.parseIp("127.0.0.1", 8080);
    const tracker_address = try std.net.Address.parseIp("127.0.0.1", 8080);
    try std.testing.expectError(
        ClientFactory.Errors.InvalidTrackerType,
        factory.get(.http, self_address, tracker_address, logAnnounceCb, &loop),
    );
}

test "does not return error when called for udp tracker" {
    const allocator = std.testing.allocator;
    var factory = ClientFactory.init(allocator);
    defer factory.deinit();

    var loop: xev.Loop = undefined;
    const self_address = try std.net.Address.parseIp("127.0.0.1", 8080);
    const tracker_address = try std.net.Address.parseIp("127.0.0.1", 8080);
    _ = try factory.get(.udp, self_address, tracker_address, logAnnounceCb, &loop);
    // try tracker.announce(undefined);
}

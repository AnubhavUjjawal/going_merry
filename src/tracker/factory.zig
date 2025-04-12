const std = @import("std");
const xev = @import("xev");
const interface = @import("interface.zig");
const udp = @import("udp.zig");

const log = std.log.scoped(.tracker);

pub const Factory = struct {
    pub const Type = enum {
        udp,
        http,
    };
    const Errors = error{ InvalidTrackerType, OutOfMemory };
    const Self = @This();

    /// To keep track of allocated memory. useful in deinit calls.
    udp_trackers: std.ArrayList(*udp.Tracker),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        const udp_trackers = std.ArrayList(*udp.Tracker).init(allocator);
        return .{
            .allocator = allocator,
            .udp_trackers = udp_trackers,
        };
    }

    pub fn deinit(self: *Self) void {
        defer self.udp_trackers.deinit();
        for (self.udp_trackers.items) |item| {
            self.allocator.destroy(item);
        }
    }

    pub fn get(
        self: *Self,
        typ: Type,
        callback: interface.Tracker.AnnounceFunctionCallback,
        /// NOTE: Currently we do not support multiple event queue implementations,
        /// in the future however, we would like to support them.
        event_loop: *xev.Loop,
    ) Errors!interface.Tracker {
        switch (typ) {
            .udp => {
                var instance = try self.allocator.create(udp.Tracker);
                try self.udp_trackers.append(instance);

                instance.* = .{
                    .announceCallback = callback,
                    .event_loop = event_loop,
                };
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
fn logAnnounceCb(data: interface.Tracker.AnnounceResponse) anyerror!void {
    log.info("got data back {any}", .{data});
}

test "return error on unimplemented tracker types" {
    const allocator = std.testing.allocator;
    var factory = Factory.init(allocator);
    var loop: xev.Loop = undefined;

    try std.testing.expectError(
        Factory.Errors.InvalidTrackerType,
        factory.get(.http, logAnnounceCb, &loop),
    );
}

test "does not return error when called for udp tracker" {
    const allocator = std.testing.allocator;
    var factory = Factory.init(allocator);
    defer factory.deinit();

    var loop: xev.Loop = undefined;
    _ = try factory.get(.udp, logAnnounceCb, &loop);
    // try tracker.announce(undefined);
}

const std = @import("std");
const interface = @import("interface.zig");

const log = std.log.scoped(.tracker);

pub const Tracker = struct {
    const Self = @This();

    fn announce(_: *anyopaque, _: interface.Tracker.Event) !void {
        // const self: *UDPTracker = @ptrCast(@alignCast(ptr));
    }

    pub fn adapt(self: *Self) interface.Tracker {
        return .{
            .ptr = self,
            .announceFn = announce,
        };
    }
};

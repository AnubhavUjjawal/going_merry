const std = @import("std");
const xev = @import("xev");
const interface = @import("interface.zig");

const log = std.log.scoped(.tracker);

pub const Tracker = struct {
    announceCallback: interface.Tracker.AnnounceFunctionCallback,
    event_loop: *xev.Loop,

    const Self = @This();

    fn announce(ptr: *anyopaque, _: interface.Tracker.AnnounceRequest) !void {
        const self: *Tracker = @ptrCast(@alignCast(ptr));

        // TODO: catch and log the error
        try self.announceCallback(undefined);
    }

    pub fn adapt(self: *Self) interface.Tracker {
        return .{
            .ptr = self,
            ._announceFn = announce,
        };
    }
};

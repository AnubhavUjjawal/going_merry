const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const log = std.log.scoped(.signals);

/// This is a global flag. Different parts of the
/// system should use @atomicLoad to check this and perform
/// cleanups so that we can exit.
pub var shutdown_initiated = false;

fn shutdown_handler(sig: c_int) callconv(.C) void {
    log.info("signal received: {d}", .{sig});
    @atomicStore(bool, &shutdown_initiated, true, .unordered);

    // We can cleanly exit only if
    // event loop has stopped. NOTE that event loop will only exit on its own
    // when all the work is done.
    // log.info("debug force shutdown is ON", .{});
    // std.posix.exit(0);
}

/// https://www.man7.org/linux/man-pages/man7/signal.7.html
/// Each signal has a current disposition by default, which determines how the
/// process behaves when it is delivered the signal. By calling `std.posix.sigaction`
/// we override the behavior.
/// TODO: windows.
pub fn setSignalHandlers() !void {
    const act = std.posix.Sigaction{
        .handler = .{ .handler = shutdown_handler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);
}

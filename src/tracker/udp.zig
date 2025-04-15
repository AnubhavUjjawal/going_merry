const std = @import("std");
const xev = @import("xev");
const interface = @import("interface.zig");
const signals = @import("../signals.zig");

const log = std.log.scoped(.tracker);
const rand = std.crypto.random;

pub const Client = struct {
    announceCallback: interface.Client.AnnounceFunctionCallback,
    event_loop: *xev.Loop,

    // connection id is returned in the response of the first request
    connection_id: ?i64,
    self_address: std.net.Address,
    tracker_address: std.net.Address,
    udp: ?*xev.UDP,
    allocator: std.mem.Allocator,
    requests_tracker: std.AutoHashMap(i32, *Request),

    const Self = @This();
    const response_buffer_size = 65_535;

    const Actions = enum(i32) {
        connect = 0,
        announce = 1,
    };

    const ConnectRequest = struct {
        protocol_id: i64 = 0x41727101980,
        transaction_id: i32,
        action: i32 = @intFromEnum(Actions.connect),
        read_buffer: *xev.WriteBuffer,
    };

    const AnnounceRequest = struct {
        data: interface.Client.AnnounceRequest,
        transaction_id: i32,
        action: i32 = @intFromEnum(Actions.announce),
        response_buffer: []u8,
        read_buffer: *xev.WriteBuffer,
    };

    const Request = union(Actions) {
        /// connect is an internal request, specific to UDP trackers and clients
        connect: *ConnectRequest,
        announce: *interface.Client.AnnounceRequest,
    };

    fn get_transaction_id(_: *Self) i32 {
        return rand.int(i32);
    }

    pub fn init(
        self_address: std.net.Address,
        tracker_address: std.net.Address,
        callback: interface.Client.AnnounceFunctionCallback,
        event_loop: *xev.Loop,
        allocator: std.mem.Allocator,
    ) Self {
        return .{
            .announceCallback = callback,
            .event_loop = event_loop,
            .connection_id = null,
            .self_address = self_address,
            .tracker_address = tracker_address,
            .udp = null,
            .allocator = allocator,
            .requests_tracker = std.AutoHashMap(i32, *Request).init(allocator),
        };
    }

    pub fn deinit(
        _: *anyopaque,
    ) void {
        // const self: *TrackerClient = @ptrCast(@alignCast(ptr));
    }

    /// announce_request needs to be passed as state, since we need to send it when we
    /// recieve the callback.
    fn connect(self: *Self, _: *interface.Client.AnnounceRequest) !void {
        // send connect request with Announce request as state, so that in the callback
        // we can set the connection id and finally send announce request.

        const transaction_id = self.get_transaction_id();
        const protocol_id: i64 = 0x41727101980;
        const action = Actions.connect;

        var arr = try self.allocator.alloc(u8, 16);
        var slice = arr[0..16];
        std.mem.writeInt(i64, slice[0..8], protocol_id, .big);
        std.mem.writeInt(i32, slice[8..12], @intFromEnum(action), .big);
        std.mem.writeInt(i32, slice[12..], transaction_id, .big);

        // const tracker_address = try std.net.Address.parseIp4("127.0.0.1", 8081);
        // const self_address = try std.net.Address.parseIp4("127.0.0.1", 8080);

        const tracker_address = try self.allocator.create(std.net.Address);
        tracker_address.* = try std.net.Address.parseIp4("127.0.0.1", 8081);

        const self_address = try self.allocator.create(std.net.Address);
        self_address.* = try std.net.Address.parseIp4("127.0.0.1", 8080);

        log.info("self: {any}, tracker: {any}", .{ self_address.*, tracker_address.* });

        self.udp = try self.allocator.create(xev.UDP);
        self.udp.?.* = try xev.UDP.init(self_address.*);
        try self.udp.?.bind(self_address.*);

        const completion = try self.allocator.create(xev.Completion);
        completion.* = .{};
        const state = try self.allocator.create(xev.UDP.State);

        // TODO: add announce request to the state
        state.* = .{
            .userdata = null,
        };
        // const response_buffer = try self.allocator.alloc(u8, response_buffer_size);
        // // const read_buffer: xev.ReadBuffer = .{ .slice = response_buffer[0..] };
        // // self.udp.?.write(
        // //     self.event_loop,
        // // );
        const write_buffer = try self.allocator.create(xev.WriteBuffer);
        write_buffer.* = .{ .slice = slice };
        self.udp.?.write(
            self.event_loop,
            completion,
            state,
            tracker_address.*,
            write_buffer.*,
            void,
            null,
            writeCallback,
        );
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
        // if (@atomicLoad(bool, &signals.shutdown_initiated, .unordered)) {
        //     return .disarm;
        // }
        return .disarm;
    }

    fn writeCallback(
        userdata: ?*void,
        loop: *xev.Loop,
        c: *xev.Completion,
        st: *xev.UDP.State,
        s: xev.UDP,
        w: xev.WriteBuffer,
        r: xev.WriteError!usize,
    ) xev.CallbackAction {
        _ = userdata;
        _ = loop;
        _ = c;
        _ = st;
        _ = s;
        _ = w;
        // _ = r;
        log.info("write callback called", .{});
        // log.info("completion: {any} {any} {any} {any}", .{ c.result, c.flags, s, });
        // const read_bytes = r catch |err| blk: {
        //     log.warn("error when reading {!}", .{err});
        //     break :blk 0;
        // };

        // switch (w) {
        //     .slice => |v| {
        //         log.info("recieved data size {d} {s}", .{ read_bytes, v[0..read_bytes] });
        //     },
        //     else => unreachable,
        // }
        if (@atomicLoad(bool, &signals.shutdown_initiated, .unordered)) {
            return .disarm;
        }
        log.info("write callback called: {any}", .{r});
        return .disarm;
    }

    // TODO: retries on getting no response.
    fn announce(ptr: *anyopaque, announce_request: *interface.Client.AnnounceRequest) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.connection_id == null) {
            log.info("since udp socket hasn't been opened yet, sending connect request first.", .{});
            try self.connect(announce_request);
        }

        // TODO: catch and log the error
        // try self.announceCallback(undefined);
    }

    pub fn adapt(self: *Self) interface.Client {
        return .{
            .ptr = self,
            ._announceFn = announce,
            ._deinit = deinit,
        };
    }
};

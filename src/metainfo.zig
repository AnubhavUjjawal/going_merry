const std = @import("std");
const bencode = @import("bencode.zig");

const Allocator = std.mem.Allocator;

pub const Manager = struct {
    const Self = @This();
    pub const MetaInfo = struct {
        /// Raw data used to build the metainfo
        _raw_content: []const u8,

        /// The URL of the tracker.
        announce: []const u8,

        /// TODO: announce list
        info: Info,

        const Info = struct {
            /// In the single file case, the name key is the name of a file,
            /// in the muliple file case, it's the name of a directory.
            name: []const u8,

            /// maps to the number of bytes in each piece the file is split into.
            /// For the purposes of transfer, files are split into fixed-size pieces
            /// which are all the same length except for possibly the last one which
            /// may be truncated. piece length is almost always a power of two,
            ///  most commonly 2 18 = 256 K (BitTorrent prior to version 3.2 uses 2 20 = 1 M as default).
            /// NOTE: in .torrent files, the key is "piece length"
            piece_length: i128,

            /// maps to a string whose length is a multiple of 20. It is to be subdivided into strings of length 20,
            /// each of which is the SHA1 hash of the piece at the corresponding index.
            pieces: []const u8,

            contents: Contents,

            const ContentsTag = enum {
                single_file,
                multiple_files,
            };

            const FileContent = struct {
                length: i128,
            };

            const MultipleFileContent = struct {
                length: i128,
                /// A list of UTF-8 encoded strings corresponding to subdirectory names,
                /// the last of which is the actual file name (a zero length list is an error case).
                path: [][]const u8,
            };

            const Contents = union(ContentsTag) {
                single_file: FileContent,
                multiple_files: []MultipleFileContent,
            };
        };

        // TODO: create deinit for clearing memory cleanly;
    };

    /// path should be relative path from working directory
    /// file should be less than 1MB size for now.
    pub fn getMetaInfoFromPath(self: *Self, path: []const u8) !MetaInfo {
        const cwd = std.fs.cwd();
        const one_mb: usize = 1000000;
        const contents = try cwd.readFileAlloc(self.allocator, path, one_mb);
        return self.getMetaInfoFromStr(contents);
    }

    pub fn getMetaInfoFromStr(self: *Self, content: []const u8) !MetaInfo {
        var bencoder = bencode.Bencoder.init(self.allocator);
        defer bencoder.deinit();
        const decoded = try bencoder.decode(content);

        return try self.getMetaInfoFromDecodeResult(content, decoded);
    }

    pub fn getMetaInfoFromDecodeResult(self: *Self, content: []const u8, decoded: bencode.Bencoder.Decoded) !MetaInfo {
        const data = decoded.result.dict;

        const announce = data.get("announce").?;

        const info = data.get("info").?;
        const name = info.dict.get("name").?;
        const piece_length = info.dict.get("piece length").?;

        const pieces = info.dict.get("pieces").?;
        const length = info.dict.get("length");

        var contents: ?MetaInfo.Info.Contents = null;

        if (length != null) {
            contents = .{
                .single_file = .{ .length = length.?.int },
            };
        } else {
            const files = info.dict.get("files").?;
            var multiple_files = std.ArrayList(MetaInfo.Info.MultipleFileContent).init(self.allocator);
            for (files.list) |file| {
                const file_length = file.dict.get("length").?;
                const path = file.dict.get("path").?;

                var path_list: [][]const u8 = try self.allocator.alloc([]const u8, path.list.len);
                for (path.list, 0..) |p, idx| {
                    path_list[idx] = p.str;
                }
                try multiple_files.append(.{
                    .length = file_length.int,
                    .path = path_list,
                });
            }
            contents = .{
                .multiple_files = try multiple_files.toOwnedSlice(),
            };
        }
        const metainfo = try self.allocator.create(MetaInfo);
        try self.memory_tracker.append(metainfo);
        metainfo.* = MetaInfo{
            .announce = announce.str,
            ._raw_content = content,
            .info = MetaInfo.Info{
                .name = name.str,
                .pieces = pieces.str,
                .piece_length = piece_length.int,
                .contents = contents.?,
            },
        };

        return metainfo.*;
    }
    memory_tracker: std.ArrayList(*MetaInfo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        const tracker = std.ArrayList(*MetaInfo).init(allocator);
        return .{
            .memory_tracker = tracker,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        defer self.memory_tracker.deinit();

        for (self.memory_tracker.items) |item| {
            self.allocator.destroy(item);
            self.allocator.free(item._raw_content);

            switch (item.info.contents) {
                .multiple_files => |v| {
                    for (v) |file| {
                        self.allocator.free(file.path);
                    }
                    self.allocator.free(v);
                },
                else => {},
            }
        }
    }
};

test "simple test reading a torrent file" {
    const allocator = std.testing.allocator;
    const path: []const u8 = "samples/big-buck-bunny.torrent";
    var manager = Manager.init(allocator);
    defer manager.deinit();

    _ = try manager.getMetaInfoFromPath(path);
    // const stdout = std.io.getStdOut().writer();
    // try std.json.stringify(contents, .{}, stdout);
}

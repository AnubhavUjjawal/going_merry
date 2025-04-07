const std = @import("std");

/// Bencoder implements the bencode encoding and decoding
/// algorithm. It provides methods to encode and decode bencoded data.
/// https://www.bittorrent.org/beps/bep_0003.html
pub const Bencoder = struct {
    const DatatypeTag = enum {
        str,
        int,
        list,
        dict,
    };

    const BencoderErrors = error{
        AllocPrintError,
        OutOfMemory,
    };

    const Datatype = union(DatatypeTag) {
        str: []const u8,
        int: i128,
        list: []const Datatype,
        dict: std.hash_map.StringHashMap(Datatype),
    };

    const Self = @This();
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// It is upto the caller to free the memory
    pub fn encode(self: *const Self, value: Datatype) BencoderErrors![]const u8 {
        switch (value) {
            .str => |v| return encodeStr(self, v),
            .int => |v| return encodeInt(self, v),
            .list => |v| return encodeList(self, v),
            else => unreachable,
        }
    }

    fn encodeStr(self: *const Self, str: []const u8) BencoderErrors![]const u8 {
        const len = str.len;
        return std.fmt.allocPrint(self.allocator, "{d}:{s}", .{ len, str });
    }

    // Integers in bencoding have no size limit, but we have to
    // use a fixed size for the encoding. We will use 128 bits
    fn encodeInt(self: *const Self, num: i128) BencoderErrors![]const u8 {
        return std.fmt.allocPrint(self.allocator, "i{d}e", .{num});
    }

    fn encodeList(self: *const Self, list: []const Datatype) BencoderErrors![]const u8 {
        var current_encoded_string: []u8 = try self.allocator.alloc(u8, 0);

        for (list) |item| {
            const result = try self.encode(item);
            defer self.allocator.free(result);

            const previous_encoded_string = current_encoded_string;
            defer self.allocator.free(previous_encoded_string);
            current_encoded_string = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ previous_encoded_string, result });
        }
        const final_encoded_string = try std.fmt.allocPrint(self.allocator, "l{s}e", .{current_encoded_string});

        defer self.allocator.free(current_encoded_string);
        return final_encoded_string;
    }
};

test "Bencoder encodeStr" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);
    const to_encode = "spam";
    const result = try bencoder.encode(.{ .str = to_encode });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("4:spam", result);
}

test "Bencoder encodeInt positive" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);
    const to_encode = 420;
    const result = try bencoder.encode(.{ .int = to_encode });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("i420e", result);
}

test "Bencoder encodeInt negative" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);
    const to_encode = -69;
    const result = try bencoder.encode(.{ .int = to_encode });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("i-69e", result);
}

test "Bencoder encodeInt zero" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);
    const to_encode = 0;
    const result = try bencoder.encode(.{ .int = to_encode });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("i0e", result);
}

test "Bencoder encodeList" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);

    const to_encode = [_]Bencoder.Datatype{
        .{ .int = 420 },
        .{ .str = "spam" },
        .{ .list = &[_]Bencoder.Datatype{ .{ .str = "spun" }, .{ .str = "eggs" } } },
        .{ .int = 69 },
    };

    const result = try bencoder.encode(.{ .list = &to_encode });
    defer allocator.free(result);
    try std.testing.expectEqualStrings("li420e4:spaml4:spun4:eggsei69ee", result);
}

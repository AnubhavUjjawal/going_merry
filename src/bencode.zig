const std = @import("std");

/// Bencoder implements the bencode encoding and decoding
/// algorithm. It provides methods to encode and decode bencoded data.
/// https://www.bittorrent.org/beps/bep_0003.html
pub const Bencoder = struct {
    pub const DatatypeTag = enum {
        str,
        int,
        list,
        dict,
    };

    const BencoderErrors = error{
        AllocPrintError,
        OutOfMemory,
        InvalidStr,
        Overflow,
        InvalidCharacter,
    };

    const StringHashMap = std.hash_map.StringHashMap(Data);

    pub const Data = union(DatatypeTag) {
        /// Strings are length-prefixed base ten followed by a colon and the string.
        /// For example 4:spam corresponds to 'spam'.
        str: []const u8,
        /// Integers are represented by an 'i' followed by the number in base 10 followed by an 'e'.
        /// For example i3e corresponds to 3 and i-3e corresponds to -3.
        /// Integers have no size limitation. i-0e is invalid. All encodings with a leading zero,
        /// such as i03e, are invalid, other than i0e, which of course corresponds to 0.
        int: i128,
        /// Lists are encoded as an 'l' followed by their elements (also bencoded) followed by an 'e'.
        /// For example l4:spam4:eggse corresponds to ['spam', 'eggs'].
        list: []const Data,
        /// Dictionaries are encoded as a 'd' followed by a list of alternating keys and their
        /// corresponding values followed by an 'e'. For example, d3:cow3:moo4:spam4:eggse corresponds to
        /// {'cow': 'moo', 'spam': 'eggs'} and d4:spaml1:a1:bee corresponds to {'spam': ['a', 'b']}.
        /// Keys must be strings and appear in sorted order (sorted as raw strings, not alphanumerics).
        dict: StringHashMap,
    };

    pub const Decoded = struct {
        result: Data,
        parsed_till: usize,
    };

    const Self = @This();
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }
    // TODO: create deinit for clearing memory cleanly when done;

    // TODO: Use logger for properly logging this
    // TODO: make it better, this prints very awkwardly.
    pub fn print(self: *const Self, value: Data) void {
        switch (value) {
            .str => |v| std.debug.print("{s} \n", .{v}),
            .int => |v| std.debug.print("{d} \n", .{v}),
            .list => |v| {
                std.debug.print("[\n", .{});
                for (v) |item| {
                    self.print(item);
                }
                std.debug.print("]\n", .{});
            },
            .dict => |v| {
                std.debug.print("{{\n", .{});
                var itr = v.keyIterator();

                var idx: usize = 0;
                while (itr.next()) |key| : (idx += 1) {
                    const val = v.get(key.*) orelse unreachable;
                    std.debug.print("{s} => ", .{key.*});
                    self.print(val);
                }
                std.debug.print("}}\n", .{});
            },
        }
    }

    /// It is upto the caller to free the memory
    pub fn encode(self: *const Self, value: Data) BencoderErrors![]const u8 {
        switch (value) {
            .str => |v| return encodeStr(self, v),
            .int => |v| return encodeInt(self, v),
            .list => |v| return encodeList(self, v),
            .dict => |v| return encodeDict(self, v),
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

    fn encodeList(self: *const Self, list: []const Data) BencoderErrors![]const u8 {
        var current_encoded_string: []u8 = try self.allocator.alloc(u8, 0);

        for (list) |item| {
            const result = try self.encode(item);
            defer self.allocator.free(result);

            const previous_encoded_string = current_encoded_string;
            current_encoded_string = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ previous_encoded_string, result });
            self.allocator.free(previous_encoded_string);
        }
        const final_encoded_string = try std.fmt.allocPrint(self.allocator, "l{s}e", .{current_encoded_string});

        self.allocator.free(current_encoded_string);
        return final_encoded_string;
    }

    fn encodeDict(self: *const Self, dict: StringHashMap) BencoderErrors![]const u8 {
        // keys must be string and appear in sorted order
        var keys: [][]const u8 = try self.allocator.alloc([]const u8, dict.count());
        defer self.allocator.free(keys);

        var itr = dict.keyIterator();

        var idx: usize = 0;
        while (itr.next()) |key| : (idx += 1) {
            keys[idx] = key.*;
        }

        // Not sure what this means: `(sorted as raw strings, not alphanumerics).`
        // so next line might not be totally correct.
        std.mem.sort([]const u8, keys, {}, stringSort);

        var current_encoded_string: []u8 = try self.allocator.alloc(u8, 0);

        for (keys) |item| {
            const value = dict.get(item) orelse unreachable;

            const result = try self.encode(.{ .str = item });
            defer self.allocator.free(result);

            const value_result = try self.encode(value);
            defer self.allocator.free(value_result);

            const previous_encoded_string = current_encoded_string;
            current_encoded_string = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ previous_encoded_string, result, value_result });
            self.allocator.free(previous_encoded_string);
        }
        const final_encoded_string = try std.fmt.allocPrint(self.allocator, "d{s}e", .{current_encoded_string});
        self.allocator.free(current_encoded_string);
        return final_encoded_string;
    }

    fn stringSort(_: void, a: []const u8, b: []const u8) bool {
        return std.mem.order(u8, a, b) == .lt;
    }

    /// It is upto the caller to free the memory
    /// We throw errors in cases of invalid strings passed
    pub fn decode(self: *const Self, str: []const u8) BencoderErrors!Decoded {
        if (str.len < 3) {
            return BencoderErrors.InvalidStr;
        }
        if (str[0] == 'i') {
            return self.decodeInt(str);
        } else if (str[0] == 'l') {
            return self.decodeList(str);
        } else if (str[0] == 'd') {
            return self.decodeDict(str);
        } else {
            return self.decodeStr(str);
        }

        unreachable;
    }

    /// Currently ignores certain illegal statuses such as leading zeroes etc.
    fn decodeInt(_: *const Self, str: []const u8) BencoderErrors!Decoded {
        // integers start with i and end with e
        // We need to find the first e
        const idx = std.mem.indexOf(u8, str, "e") orelse return BencoderErrors.InvalidStr;
        const parsed = try std.fmt.parseInt(i128, str[1..idx], 10);
        return Decoded{ .result = Data{ .int = parsed }, .parsed_till = idx };
    }

    fn decodeList(self: *const Self, str: []const u8) BencoderErrors!Decoded {
        // We need to go through every item in the list, starting from 2nd character.
        var items = std.ArrayList(Data).init(self.allocator);
        defer items.deinit();

        var idx: usize = 1;

        while (idx < str.len - 1) {
            if (str[idx] == 'e') {
                break;
            }

            const data = try self.decode(str[idx..]);
            // end is next `e` char.
            idx += 1 + data.parsed_till;
            try items.append(data.result);
        }
        return Decoded{ .result = Data{ .list = try items.toOwnedSlice() }, .parsed_till = idx };
    }

    fn decodeDict(self: *const Self, str: []const u8) BencoderErrors!Decoded {
        var dict = StringHashMap.init(self.allocator);
        // dict has alternating key value pairs
        var idx: usize = 1;
        while (idx < str.len - 1) {
            if (str[idx] == 'e') {
                break;
            }
            const key = try self.decode(str[idx..]);
            idx += 1 + key.parsed_till;
            const value = try self.decode(str[idx..]);
            idx += 1 + value.parsed_till;
            try dict.put(key.result.str, value.result);
        }

        return Decoded{ .parsed_till = idx, .result = Data{ .dict = dict } };
    }

    fn decodeStr(_: *const Self, str: []const u8) BencoderErrors!Decoded {
        // split the str by the first :
        const idx = std.mem.indexOf(u8, str, ":") orelse return BencoderErrors.InvalidStr;

        // cast from 0..idx to a number, that is the length of the string
        const size = try std.fmt.parseInt(i32, str[0..idx], 10);

        const start_idx = idx + 1;
        const end_idx = (idx + 1 + @as(usize, @intCast(size)));
        const parsed = str[start_idx..end_idx];
        return Decoded{ .result = Data{ .str = parsed }, .parsed_till = end_idx - 1 };
    }
};

test "Bencoder decodeList" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);
    const to_decode = "li420ei-69e4:spame";
    const decoded = try bencoder.decode(to_decode);
    defer allocator.free(decoded.result.list);
    try std.testing.expectEqual(420, decoded.result.list[0].int);
    try std.testing.expectEqual(-69, decoded.result.list[1].int);
    try std.testing.expectEqualStrings("spam", decoded.result.list[2].str);
}

test "Bencoder decodeList list of lists" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);
    const to_decode = "li420eli420ei-69e4:spame4:eggse";
    const decoded = try bencoder.decode(to_decode);
    defer allocator.free(decoded.result.list);
    defer allocator.free(decoded.result.list[1].list);
    try std.testing.expectEqual(420, decoded.result.list[0].int);

    // list of list assertions
    try std.testing.expectEqual(420, decoded.result.list[1].list[0].int);
    try std.testing.expectEqual(-69, decoded.result.list[1].list[1].int);
    try std.testing.expectEqualStrings("spam", decoded.result.list[1].list[2].str);

    try std.testing.expectEqualStrings("eggs", decoded.result.list[2].str);
}

test "Bencoder decodeDict" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);
    const to_decode = "d4:key15:valu14:key2i123e4:key3i-123e4:key4l1:a1:bl1:c3:def1:gi1ei234ei-420eeee";
    var decoded = try bencoder.decode(to_decode);
    defer decoded.result.dict.deinit();
    const list_data = decoded.result.dict.get("key4") orelse unreachable;
    defer allocator.free(list_data.list);
    defer allocator.free(list_data.list[2].list);

    const key1_value = decoded.result.dict.get("key1") orelse unreachable;
    try std.testing.expectEqualStrings("valu1", key1_value.str);

    const key2_value = decoded.result.dict.get("key2") orelse unreachable;
    try std.testing.expectEqual(123, key2_value.int);

    const key3_value = decoded.result.dict.get("key3") orelse unreachable;
    try std.testing.expectEqual(-123, key3_value.int);

    // TODO: more expects
}

test "Bencoder decodeStr" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);
    const to_decode = "4:spam";
    const decoded = try bencoder.decode(to_decode);
    try std.testing.expectEqualStrings("spam", decoded.result.str);
}

test "Bencoder decodeInt positive" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);
    const to_decode = "i420e";
    const decoded = try bencoder.decode(to_decode);
    try std.testing.expectEqual(420, decoded.result.int);
}

test "Bencoder decodeInt negative" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);
    const decoded = "i-420e";
    const result = try bencoder.decode(decoded);
    try std.testing.expectEqual(-420, result.result.int);
}

test "Bencoder decodeInt zero" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);
    const decoded = "i0e";
    const result = try bencoder.decode(decoded);
    try std.testing.expectEqual(0, result.result.int);
}

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

    const to_encode = [_]Bencoder.Data{
        .{ .int = 420 },
        .{ .str = "spam" },
        .{ .list = &[_]Bencoder.Data{ .{ .str = "spun" }, .{ .str = "eggs" } } },
        .{ .int = 69 },
    };

    const result = try bencoder.encode(.{ .list = &to_encode });
    defer allocator.free(result);
    try std.testing.expectEqualStrings("li420e4:spaml4:spun4:eggsei69ee", result);
}

test "Bencoder encodeDict" {
    const allocator = std.testing.allocator;
    const bencoder = Bencoder.init(allocator);

    var hashMap = Bencoder.StringHashMap.init(allocator);
    defer hashMap.deinit();
    try hashMap.put("cow1", .{ .str = "moo1" });
    try hashMap.put("spam", .{ .str = "eggs" });
    try hashMap.put("cow2", .{ .str = "moo2" });
    try hashMap.put("list", .{ .list = &[_]Bencoder.Data{
        .{ .int = 420 },
        .{ .str = "spam" },
        .{ .list = &[_]Bencoder.Data{ .{ .str = "spun" }, .{ .str = "eggs" } } },
        .{ .int = 69 },
    } });
    const to_encode = Bencoder.Data{ .dict = hashMap };

    const result = try bencoder.encode(to_encode);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("d4:cow14:moo14:cow24:moo24:listli420e4:spaml4:spun4:eggsei69ee4:spam4:eggse", result);
}

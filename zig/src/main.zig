const std = @import("std");
const expect = std.testing.expect;
const expectEqualSlices = std.testing.expectEqualSlices;
const Allocator = std.mem.Allocator;
const SinglyLinkedList = std.SinglyLinkedList;

const Types = enum(u4) {
    zigzag,
    float,
    simple,
    ref,
    reserved_4,
    reserved_5,
    reserved_6,
    reserved_7,
    bytes,
    utf8,
    hexstring,
    list,
    map,
    array,
    trie,
    scope,
};

const SubTypes = enum {
    false,
    true,
    null,
};

fn zigzag_encode(num: i64) u64 {
    return @bitCast(u64, (num >> 63) ^ (num << 1));
}

fn zigzag_decode(num: u64) i64 {
    return @bitCast(i64, num >> 1) ^ -(@bitCast(i64, num) & 1);
}

fn float_encode(num: f64) u64 {
    // Hard code all NaNs to match V8 JavaScript
    if (std.math.isNan(num)) {
        return 0x7ff8000000000000;
    }
    return @bitCast(u64, num);
}

fn float_decode(num: u64) f64 {
    return @bitCast(f64, num);
}

const EncoderValue = union(enum) {
    pair: struct {
        small: u4,
        big: u64,
    },
    buf: []u8,
    hex: []u8,
};

const EncoderNode = struct {
    data: EncoderValue,
    next: ?*EncoderNode,
};

const nib_5 = packed struct(u8) { tag: u4, small: u4 };
const nib_8 = packed struct(u16) { tag: u4, small: u4, big: u8 };
const nib_16 = packed struct(u24) { tag: u4, small: u4, big: u16 };
const nib_32 = packed struct(u40) { tag: u4, small: u4, big: u32 };
const nib_64 = packed struct(u72) { tag: u4, small: u4, big: u64 };

fn encode_pair(allocator: *const Allocator, small: u4, big: u64) ![]u8 {
    if (big < 12) {
        const encoded: *nib_5 = try allocator.create(nib_5);
        encoded.tag = @intCast(u4, big);
        encoded.small = small;
        return @ptrCast(*[1]u8, encoded);
    }
    if (big < 0x100) {
        const encoded: *nib_8 = try allocator.create(nib_8);
        encoded.tag = 12;
        encoded.small = small;
        encoded.big = @intCast(u8, big);
        return @ptrCast(*[2]u8, encoded);
    }
    if (big < 0x10000) {
        const encoded: *nib_16 = try allocator.create(nib_16);
        encoded.tag = 13;
        encoded.small = small;
        encoded.big = @intCast(u16, big);
        return @ptrCast(*[3]u8, encoded);
    }
    if (big < 0x100000000) {
        const encoded: *nib_32 = try allocator.create(nib_32);
        encoded.tag = 14;
        encoded.small = small;
        encoded.big = @intCast(u32, big);
        return @ptrCast(*[5]u8, encoded);
    }
    const encoded: *nib_64 = try allocator.create(nib_64);
    encoded.tag = 15;
    encoded.small = small;
    encoded.big = big;
    return @ptrCast(*[9]u8, encoded);
}

fn encode_integer(allocator: *const Allocator, n: i64) !*EncoderNode {
    var node = try allocator.create(EncoderNode);
    node.data.pair = .{ .small = @enumToInt(Types.zigzag), .big = zigzag_encode(n) };
    return node;
}

// fn encode_float(allocator: *const Allocator, n: f64) ![]u8 {
//     return encode_pair(allocator, @enumToInt(Types.float), float_encode(n));
// }

// fn encode_boolean(allocator: *const Allocator, v: bool) ![]u8 {
//     const e = if (v) SubTypes.true else SubTypes.false;
//     return encode_pair(allocator, @enumToInt(Types.simple), @enumToInt(e));
// }

// fn encode_null(allocator: *const Allocator) ![]u8 {
//     return encode_pair(allocator, @enumToInt(Types.simple), @enumToInt(SubTypes.null));
// }

// // // const L = SinglyLinkedList([]u8);

// // fn encode_string(allocator: *const Allocator, str: []u8) !*L {
// //     var head = try allocator.create(L.Node);
// //     head.data = try encode_pair(allocator, @enumToInt(Types.utf8), str.len);
// //     var body = try allocator.create(L.Node);
// //     body.data = str;
// //     var list = try allocator.create(L);
// //     list.prepend(head);
// //     head.insertAfter(body);
// //     return list;
// // }

fn get_size(val: EncoderValue) u64 {
    return switch (val) {
        EncoderValue.pair => |pair| if (pair.big < 12) 1 else if (pair.big < 0x100) 2 else if (pair.big < 0x10000) 3 else if (pair.big < 0x100000000) 5 else 9,
        EncoderValue.buf => |buf| buf.len,
        EncoderValue.hex => |hex| hex.len >> 1,
    };
}

fn flatten(allocator: *const Allocator, root: *EncoderNode) ![]u8 {
    var len = get_size(root);

    var buf = allocator.alloc(u8, len);

    // len = 0;
    // {
    //     var it = list.first;
    //     while (it) |node| : (it = node.next) {
    //         std.mem.copy(u8, (buf.*)[len .. len + node.data.len], node.data);
    //         len = len + node.data.len;
    //     }
    // }

    return buf;
}

test "zigzag encode" {
    try expect(zigzag_encode(0) == 0);
    try expect(zigzag_encode(-1) == 1);
    try expect(zigzag_encode(1) == 2);
    try expect(zigzag_encode(0x7fffffffffffffff) == 0xfffffffffffffffe);
    try expect(zigzag_encode(-0x8000000000000000) == 0xffffffffffffffff);
}

test "zigzag decode" {
    try expect(zigzag_decode(0) == 0);
    try expect(zigzag_decode(1) == -1);
    try expect(zigzag_decode(2) == 1);
    try expect(zigzag_decode(0xfffffffffffffffe) == 0x7fffffffffffffff);
    try expect(zigzag_decode(0xffffffffffffffff) == -0x8000000000000000);
}

test "float encode" {
    try expect(float_encode(-0.1) == 0xbfb999999999999a);
    try expect(float_encode(0.1) == 0x3fb999999999999a);
    try expect(float_encode(-1.1) == 0xbff199999999999a);
    try expect(float_encode(1.1) == 0x3ff199999999999a);
}

test "float decode" {
    try expect(float_decode(0xbfb999999999999a) == -0.1);
    try expect(float_decode(0x3fb999999999999a) == 0.1);
    try expect(float_decode(0xbff199999999999a) == -1.1);
    try expect(float_decode(0x3ff199999999999a) == 1.1);
}

// test "encode pair" {
//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     defer arena.deinit();
//     const allocator = arena.allocator();

//     try expectEqualSlices(u8, "\x10", try encode_pair(&allocator, 1, 0));
//     try expectEqualSlices(u8, "\x1b", try encode_pair(&allocator, 1, 11));
//     try expectEqualSlices(u8, "\xf1", try encode_pair(&allocator, 15, 1));
//     try expectEqualSlices(u8, "\xfa", try encode_pair(&allocator, 15, 10));
//     try expectEqualSlices(u8, "\x5c\x13", try encode_pair(&allocator, 5, 0x13));
//     try expectEqualSlices(u8, "\x4d\xcf\x07", try encode_pair(&allocator, 4, 0x7cf));
//     try expectEqualSlices(u8, "\x3e\x3f\x0d\x03\x00", try encode_pair(&allocator, 3, 0x30d3f));
//     try expectEqualSlices(u8, "\x2f\xff\xc7\x17\xa8\x04\x00\x00\x00", try encode_pair(&allocator, 2, 0x4a817c7ff));
// }

test "encode integer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try expectEqualSlices(u8, "\x00", try flatten(&allocator, try encode_integer(&allocator, 0)));
    // try expectEqualSlices(u8, "\x01", try encode_integer(&allocator, -1));
    // try expectEqualSlices(u8, "\x02", try encode_integer(&allocator, 1));
    // try expectEqualSlices(u8, "\x0c\x13", try encode_integer(&allocator, -10));
    // try expectEqualSlices(u8, "\x0c\x14", try encode_integer(&allocator, 10));
    // try expectEqualSlices(u8, "\x0d\xcf\x07", try encode_integer(&allocator, -1000));
    // try expectEqualSlices(u8, "\x0d\xd0\x07", try encode_integer(&allocator, 1000));
    // try expectEqualSlices(u8, "\x0e\xff\x93\x35\x77", try encode_integer(&allocator, -1000000000));
    // try expectEqualSlices(u8, "\x0e\x00\x94\x35\x77", try encode_integer(&allocator, 1000000000));
    // try expectEqualSlices(u8, "\x0f\xff\xff\xc7\x4e\x67\x6d\xc1\x1b", try encode_integer(&allocator, -1000000000000000000));
    // try expectEqualSlices(u8, "\x0f\x00\x00\xc8\x4e\x67\x6d\xc1\x1b", try encode_integer(&allocator, 1000000000000000000));
    // try expectEqualSlices(u8, "\x0f\xfd\xff\xff\xff\xff\xff\xff\xff", try encode_integer(&allocator, -9223372036854775807));
    // try expectEqualSlices(u8, "\x0f\xfe\xff\xff\xff\xff\xff\xff\xff", try encode_integer(&allocator, 9223372036854775807));
    // try expectEqualSlices(u8, "\x0f\xff\xff\xff\xff\xff\xff\xff\xff", try encode_integer(&allocator, -9223372036854775808));
}

// test "encode float" {
//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     defer arena.deinit();
//     const allocator = arena.allocator();

//     try expectEqualSlices(u8, "\x1f\x9a\x99\x99\x99\x99\x99\xb9\xbf", try encode_float(&allocator, -0.1));
//     try expectEqualSlices(u8, "\x1f\x9a\x99\x99\x99\x99\x99\xb9\x3f", try encode_float(&allocator, 0.1));
//     try expectEqualSlices(u8, "\x1f\x9a\x99\x99\x99\x99\x99\xf1\xbf", try encode_float(&allocator, -1.1));
//     try expectEqualSlices(u8, "\x1f\x9a\x99\x99\x99\x99\x99\xf1\x3f", try encode_float(&allocator, 1.1));
//     try expectEqualSlices(u8, "\x1f\x00\x00\x00\x00\x00\x00\xf0\x7f", try encode_float(&allocator, std.math.inf(f64)));
//     try expectEqualSlices(u8, "\x1f\x00\x00\x00\x00\x00\x00\xf0\xff", try encode_float(&allocator, -std.math.inf(f64)));
//     try expectEqualSlices(u8, "\x1f\x00\x00\x00\x00\x00\x00\xf8\x7f", try encode_float(&allocator, std.math.nan(f64)));
// }

// test "encode simple" {
//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     defer arena.deinit();
//     const allocator = arena.allocator();

//     try expectEqualSlices(u8, "\x20", try encode_boolean(&allocator, false));
//     try expectEqualSlices(u8, "\x21", try encode_boolean(&allocator, true));
//     try expectEqualSlices(u8, "\x22", try encode_null(&allocator));
// }

// test "encode string" {
//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     defer arena.deinit();
//     const allocator = arena.allocator();

//     try expectEqualSlices(u8, "\x90", try flatten(&allocator, try encode_string(&allocator, "")));
//     try expectEqualSlices(u8, "\x95\x48\x65\x6c\x6c\x6f", try flatten(&allocator, try encode_string(&allocator, "Hello")));
//     try expectEqualSlices(u8, "\x95\x57\x6f\x72\x6c\x64", try flatten(&allocator, try encode_string(&allocator, "World")));
//     try expectEqualSlices(u8, "\x9b\xf0\x9f\x8f\xb5\x52\x4f\x53\x45\x54\x54\x45", try flatten(&allocator, try encode_string(&allocator, "🏵ROSETTE")));
//     try expectEqualSlices(u8, "\x9c\x18\xf0\x9f\x9f\xa5\xf0\x9f\x9f\xa7\xf0\x9f\x9f\xa8\xf0\x9f\x9f\xa9\xf0\x9f\x9f\xa6\xf0\x9f\x9f\xaa", try flatten(&allocator, try encode_string(&allocator, "🟥🟧🟨🟩🟦🟪")));
//     try expectEqualSlices(u8, "\x96\xf0\x9f\x91\xb6\x57\x48", try flatten(&allocator, try encode_string(&allocator, "👶WH")));
// }

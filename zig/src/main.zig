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
    return @bitCast(u64, num);
}

fn float_decode(num: u64) f64 {
    return @bitCast(f64, num);
}

const write_fn = *const fn (pow: u2, val: u64) void;

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

test "encode pair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try expectEqualSlices(u8, "\x10", try encode_pair(&allocator, 1, 0));
    try expectEqualSlices(u8, "\x1b", try encode_pair(&allocator, 1, 11));
    try expectEqualSlices(u8, "\xf1", try encode_pair(&allocator, 15, 1));
    try expectEqualSlices(u8, "\xfa", try encode_pair(&allocator, 15, 10));
    try expectEqualSlices(u8, "\x0c\x13", try encode_pair(&allocator, 0, 0x13));
    std.debug.print("[[{.}]]", .{std.fmt.fmtSliceHexLower(try encode_pair(&allocator, 0, 0x07cf))});
    try expectEqualSlices(u8, "\x0d\xcf\x07", try encode_pair(&allocator, 0, 0x07cf));
}

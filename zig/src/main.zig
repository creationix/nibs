const std = @import("std");
const testing = std.testing;

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

fn encode_pair(small: u4, big: u64, write: write_fn) u64 {
    const high = @intCast(u64, small) << 4;
    if (big < 12) {
        write(0, high | big);
        return 1;
    }
    if (big < 0x100) {
        write(0, high | 12);
        write(0, big);
        return 2;
    }
    if (big < 0x10000) {
        write(0, high | 13);
        write(1, big);
        return 3;
    }
    if (big < 0x100000000) {
        write(0, high | 14);
        write(2, big);
        return 5;
    }
    write(0, high | 15);
    write(3, big);
    return 9;
}

test "zigzag encode" {
    try testing.expect(zigzag_encode(0) == 0);
    try testing.expect(zigzag_encode(-1) == 1);
    try testing.expect(zigzag_encode(1) == 2);
    try testing.expect(zigzag_encode(0x7fffffffffffffff) == 0xfffffffffffffffe);
    try testing.expect(zigzag_encode(-0x8000000000000000) == 0xffffffffffffffff);
}

test "zigzag decode" {
    try testing.expect(zigzag_decode(0) == 0);
    try testing.expect(zigzag_decode(1) == -1);
    try testing.expect(zigzag_decode(2) == 1);
    try testing.expect(zigzag_decode(0xfffffffffffffffe) == 0x7fffffffffffffff);
    try testing.expect(zigzag_decode(0xffffffffffffffff) == -0x8000000000000000);
}

test "float encode" {
    try testing.expect(float_encode(-0.1) == 0xbfb999999999999a);
    try testing.expect(float_encode(0.1) == 0x3fb999999999999a);
    try testing.expect(float_encode(-1.1) == 0xbff199999999999a);
    try testing.expect(float_encode(1.1) == 0x3ff199999999999a);
}

test "float decode" {
    try testing.expect(float_decode(0xbfb999999999999a) == -0.1);
    try testing.expect(float_decode(0x3fb999999999999a) == 0.1);
    try testing.expect(float_decode(0xbff199999999999a) == -1.1);
    try testing.expect(float_decode(0x3ff199999999999a) == 1.1);
}

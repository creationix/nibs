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
    const unum = @cast(u64, num);
    return (unum >> 63) ^ (unum << 1);
}

test "zigzag encode" {
    try testing.expect(zigzag_encode(0) == 0);
    try testing.expect(zigzag_encode(-1) == 1);
    try testing.expect(zigzag_encode(1) == 2);
    // try testing.expect(zigzag_encode(9223372036854775807) == 0x0fffffffffffffefff);
    try testing.expect(zigzag_encode(-9223372036854775808) == 0x0fffffffffffffffff);
}

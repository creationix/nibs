require 'test-utils'
local NibLib = require 'nib-lib'
local U8Ptr = NibLib.U8Ptr
local ffi = require 'ffi'
local cast = ffi.cast

local xxh64 = require 'xxhash64'
local xxh32 = require 'xxhash32'
local color = require('pretty-print').color

local tests = {
    { "", 0, 0x02cc5d05, 0xef46db3751d8e999ULL },
    { "", 1, 0x0b2cb792, 0xd5afba1336a3be4bULL },
    { "a", 0, 0x550d7456, 0xd24ec4f1a98c6e5bULL },
    { "as", 0, 0x9d5a0464, 0x1c330fb2d66be179ULL },
    { "asd", 0, 0x3d83552b, 0x631c37ce72a97393ULL },
    { "asdf", 0, 0x5e702c32, 0x415872f599cea71eULL },
    { "Call me Ishmael.",
        0, 0x02f60492, 0x6d04390fc9d61a90ULL },
    { "Some years ago--never mind how long precisely-",
        0, 0x5f85f0d4, 0x8f26f2b986afdc52ULL },
    -- Exactly 63 characters, which exercises all code paths.
    { "Call me Ishmael. Some years ago--never mind how long precisely-",
        0, 0x6f320359, 0x02a2e85470d6fd96ULL },
    { "0123456789abcdef",
        0, 0xc2c45b69, 0x5c5b90c34e376d0bULL },
    { "0123456789abcdef0123456789abcdef",
        0, 0xeb888d30, 0x642a94958e71e6c5ULL },
}
local good = color "success"
local bad = color "failure"
local reset = color ""
for _, t in ipairs(tests) do
    local input, seed, expected_h32, expected_h64 = table.unpack(t)
    local ptr = cast(U8Ptr, input)
    local len = #input
    local h32 = xxh32(ptr, len, seed)
    local h64 = xxh64(ptr, len, seed)
    print(string.format("%q, %d, %s%s%s, %s%s%s",
        input, seed,
        h32 == expected_h32 and good or bad, bit.tohex(h32), reset,
        h64 == expected_h64 and good or bad, bit.tohex(h64), reset
    ))
    assert(h32 == expected_h32, "xxh32 mismatch")
    assert(h64 == expected_h64, "xxh64 mismatch")
end

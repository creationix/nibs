local ffi = require 'ffi'
local xxh64 = require 'xxhash64'
local xxh32 = require 'xxhash32'
local color = require('pretty-print').color

local function hex(h)
    return loadstring('return "' .. h:gsub("..", function(b) return "\\x" .. b end) .. '"')()
end

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

    -- Common nibs values

    -- Int(0-6)
    { hex "00", 0, 0xcf65b03e, 0xe934a84adb052768ULL },
    { hex "02", 0, 0xd5403278, 0x4b79b8c95732b0e7ULL },
    { hex "04", 0, 0xebc0cebc, 0x64b9da3ed69d6732ULL },
    { hex "06", 0, 0xc9b8f720, 0x5896bb9a27ab7ba5ULL },
    { hex "08", 0, 0x452b0672, 0x431f0f810a7002a7ULL },
    { hex "0a", 0, 0x81c9d352, 0xcafc7706cee4572bULL },
    { hex "0c0c", 0, 0x77cab09a, 0x90f2cfe93880eb7bULL },
    -- false/true/null
    { hex "20", 0, 0x072e1494, 0x079cf5ceb668638dULL },
    { hex "21", 0, 0x9c4e9f74, 0x9ea4029ff0912cb8ULL },
    { hex "22", 0, 0x99ae6e62, 0x89f45523b5b446aeULL },
    -- pi/inf/-inf/nan
    { hex "1f182d4454fb210940", 0, 0x36a39797, 0x954ccee0fb5ee767ULL },
    { hex "1f000000000000f07f", 0, 0x64f4be21, 0x04e80133d19091d6ULL },
    { hex "1f000000000000f0ff", 0, 0x06e6a447, 0xf6b64012a65883f6ULL },
    { hex "1f000000000000f8ff", 0, 0xf755ac37, 0x7406dc284ae4491cULL },
}
local good = color "success"
local bad = color "failure"
local reset = color ""
for _, t in ipairs(tests) do
    local input, seed, expected_h32, expected_h64 = table.unpack(t)
    local ptr = ffi.new("const char*", input)
    local len = #input
    local h32 = xxh32(ptr, len, seed)
    local h64 = xxh64(ptr, len, seed)
    print(string.format("%q, %d, %s%sx%s, %s%s%s",
        input, seed,
        h32 == expected_h32 and good or bad, bit.tohex(h32), reset,
        h64 == expected_h64 and good or bad, bit.tohex(h64), reset
    ))
    assert(h32 == expected_h32, "xxh32 mismatch")
    assert(h64 == expected_h64, "xxh64 mismatch")
end

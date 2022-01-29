local bit = require 'bit'
local ffi = require 'ffi'
local sizeof = ffi.sizeof
local tohex = bit.tohex
local byte = string.byte
local char = string.char
local concat = table.concat

local Nibs = require './encode-nibs.lua'

local tests = {
    -- Integer
    1, "\x01",
    42, "\x0c\x2a",
    500, "\x0d\xf4\x01",
    0xdeadbeef, "\x0e\xef\xbe\xad\xde",
    -- NegInt
    -1, "\x11",
    -42, "\x1c\x2a",
    -500, "\x1d\xf4\x01",
    -0xdeadbeef, "\x1e\xef\xbe\xad\xde",
    -- Simple
    false, "\x20",
    true, "\x21",
    nil, "\x22",
    -- binary
    -- null terminated C string
    ffi.new("const char*", "Binary!"), "\x48Binary!\0",
    -- C byte array
    ffi.new("uint8_t[3]", {1,2,3}), "\x43\x01\x02\x03",
    -- C double array
    ffi.new("double[1]", {math.pi}), "\x48\x18\x2d\x44\x54\xfb\x21\x09\x40",
    -- string
    "Hello", "\x55Hello",
    -- list
    {1,2,3}, "\x63\x01\x02\x03",
    -- map
    {name="Tim"},"\x79\x54name\x53Tim",
}

local function dump_string(str)
    local parts = {}
    for i = 1, #str do
        parts[i] = "\\x" .. tohex(byte(str, i),2)
    end
    return '"' .. concat(parts) .. '"'
end

for i = 1, #tests, 2 do
    local input = tests[i]
    local expected = tests[i+1]
    local buf = Nibs.encode(input)
    local str = ffi.string(buf, sizeof(buf))
    p(input, str)
    print(dump_string(str))
    assert(ffi.string(buf, sizeof(buf)) == expected)
end

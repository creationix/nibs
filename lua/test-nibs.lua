local bit = require 'bit'
local ffi = require 'ffi'
local sizeof = ffi.sizeof
local tohex = bit.tohex
local byte = string.byte
local concat = table.concat

local Nibs = require './nibs.lua'

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
    -- Binary
    -- null terminated C string
    ffi.new("const char*", "Binary!"), "\x48Binary!\0",
    -- C byte array
    ffi.new("uint8_t[3]", {1,2,3}), "\x43\x01\x02\x03",
    -- C double array
    ffi.new("double[1]", {math.pi}), "\x48\x18\x2d\x44\x54\xfb\x21\x09\x40",
    -- String
    "Hello", "\x55Hello",
    -- list
    {1,2,3}, "\x63\x01\x02\x03",
    -- map
    {name="Tim"},"\x79\x54name\x53Tim",
    {{[10]=100,[20]=50,[true]=false},{foo=true}},
        "\x6c\x10\x79\x21\x20\x0a\x0c\x64\x0c\x14\x0c\x32\x75\x53\x66\x6f\x6f\x21",
}

local function dump_string(str)
    local parts = {}
    for i = 1, #str do
        parts[i] = "\\x" .. tohex(byte(str, i),2)
    end
    return '"' .. concat(parts) .. '"'
end

local function equal(a,b)
    if a == b then return true end
    local kind = type(a)
    if kind ~= type(b) then return false end
    if kind == "cdata" then
        local len = sizeof(a)
        if len ~= sizeof(b) then return false end
        local abin = ffi.cast("const uint8_t*", a)
        local bbin = ffi.cast("const uint8_t*", b)
        for i = 0, len - 1 do
            if abin[i] ~= bbin[i] then return false end
        end
        return true
    end
    if kind == "table" then
        if #a ~= #b then return false end
        for k, v in pairs(a) do
            if not equal(v,b[k]) then return false end
        end
        for k, v in pairs(b) do
            if not equal(v,a[k]) then return false end
        end
        return true
    end
    if kind == "number" or kind == "string" or kind == "boolean" then
        return false
    end
    error("Unknown Type: " .. kind)
end

for i = 1, #tests, 2 do
    print()
    local input = tests[i]
    p("input", input)
    local expected = tests[i+1]
    local buf = Nibs.encode(input)
    local str = ffi.string(buf, sizeof(buf))
    p("encoded", str)
    print("'encoded'\t" .. dump_string(str))
    assert(ffi.string(buf, sizeof(buf)) == expected)
    local decoded = Nibs.decode(buf)
    p("decoded", decoded)
    assert(equal(decoded, input), "decode failed")
end

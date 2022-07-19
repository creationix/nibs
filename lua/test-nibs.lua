local p = require('pretty-print').prettyPrint
local bit = require 'bit'
local rshift = bit.rshift
local ffi = require 'ffi'
local sizeof = ffi.sizeof
local tohex = bit.tohex
local istype = ffi.istype
local copy = ffi.copy

local byte = string.byte
local concat = table.concat

local Nibs = require 'nibs'
local nibs = Nibs.new()
local Ordered = require 'ordered'
local OrderedMap = Ordered.OrderedMap
local OrderedList = Ordered.OrderedList

local Zero = {id=0,name="Zero"}
local One = {id=1,name="One"}
local Two = {id=2,name="Two"}
local Three = "Three"
nibs.registerRef(0, Zero)
nibs.registerRef(1, One)
nibs.registerRef(2, Two)
nibs.registerRef(3, Three)

local F32Array = ffi.typeof "float[?]"

nibs.registerTag(0,
    function (val) -- encode from F32Array to nibs binary
        return istype(F32Array, val) and val or nil
    end,
    function (val) -- decode from nibs binary to F32Array
        local len = sizeof(val)
        local arr = F32Array(rshift(len,2))
        copy(arr, val, len)
        return arr
    end
)

local function Tuple(...)
    return OrderedList.new(...)
end

local function Map(...)
    return OrderedMap.new(...)
end

local function Array(...)
    return OrderedList.new(...)
end

local function Binary(...)
    return ffi.new("uint8_t[?]", select("#", ...), {...})
end

local tests = {
    -- ZigZag Integer
    0, "\x00", 0,
    0x1, "\x02", 0x1,
    0x10, "\x0c\x20", 0x10,
    0x100, "\x0d\x00\x02", 0x100,
    0x1000, "\x0d\x00\x20", 0x1000,
    0x10000, "\x0e\x00\x00\x02\x00", 0x10000,
    0x100000, "\x0e\x00\x00\x20\x00", 0x100000,
    0x1000000, "\x0e\x00\x00\x00\x02", 0x1000000,
    0x10000000, "\x0e\x00\x00\x00\x20", 0x10000000,
    0x100000000, "\x0f\x00\x00\x00\x00\x02\x00\x00\x00", 0x100000000,
    0x1000000000, "\x0f\x00\x00\x00\x00\x20\x00\x00\x00", 0x1000000000,
    0x10000000000, "\x0f\x00\x00\x00\x00\x00\x02\x00\x00", 0x10000000000,
    0x100000000000, "\x0f\x00\x00\x00\x00\x00\x20\x00\x00", 0x100000000000,
    0x1000000000000, "\x0f\x00\x00\x00\x00\x00\x00\x02\x00", 0x1000000000000,
    0x10000000000000, "\x0f\x00\x00\x00\x00\x00\x00\x20\x00", 0x10000000000000,
    0x100000000000000, "\x0f\x00\x00\x00\x00\x00\x00\x00\x02", 0x100000000000000,
    0x1000000000000000, "\x0f\x00\x00\x00\x00\x00\x00\x00\x20", 0x1000000000000000,
    -0x1, "\x01", -0x1,
    -0x10, "\x0c\x1f", -0x10,
    -0x100, "\x0d\xff\x01", -0x100,
    -0x1000, "\x0d\xff\x1f", -0x1000,
    -0x10000, "\x0e\xff\xff\x01\x00", -0x10000,
    -0x100000, "\x0e\xff\xff\x1f\x00", -0x100000,
    -0x1000000, "\x0e\xff\xff\xff\x01", -0x1000000,
    -0x10000000, "\x0e\xff\xff\xff\x1f", -0x10000000,
    -0x100000000, "\x0f\xff\xff\xff\xff\x01\x00\x00\x00", -0x100000000,
    -0x1000000000, "\x0f\xff\xff\xff\xff\x1f\x00\x00\x00", -0x1000000000,
    -0x10000000000, "\x0f\xff\xff\xff\xff\xff\x01\x00\x00", -0x10000000000,
    -0x100000000000, "\x0f\xff\xff\xff\xff\xff\x1f\x00\x00", -0x100000000000,
    -0x1000000000000, "\x0f\xff\xff\xff\xff\xff\xff\x01\x00", -0x1000000000000,
    -0x10000000000000, "\x0f\xff\xff\xff\xff\xff\xff\x1f\x00", -0x10000000000000,
    -0x100000000000000LL, "\x0f\xff\xff\xff\xff\xff\xff\xff\x01", -0x100000000000000LL,
    -0x1000000000000000LL, "\x0f\xff\xff\xff\xff\xff\xff\xff\x1f", -0x1000000000000000LL,
    0x11, "\x0c\x22", 0x11,
    0x101, "\x0d\x02\x02", 0x101,
    0x1001, "\x0d\x02\x20", 0x1001,
    0x10001, "\x0e\x02\x00\x02\x00", 0x10001,
    0x100001, "\x0e\x02\x00\x20\x00", 0x100001,
    0x1000001, "\x0e\x02\x00\x00\x02", 0x1000001,
    0x10000001, "\x0e\x02\x00\x00\x20", 0x10000001,
    0x100000001, "\x0f\x02\x00\x00\x00\x02\x00\x00\x00", 0x100000001,
    0x1000000001, "\x0f\x02\x00\x00\x00\x20\x00\x00\x00", 0x1000000001,
    0x10000000001, "\x0f\x02\x00\x00\x00\x00\x02\x00\x00", 0x10000000001,
    0x100000000001, "\x0f\x02\x00\x00\x00\x00\x20\x00\x00", 0x100000000001,
    0x1000000000001, "\x0f\x02\x00\x00\x00\x00\x00\x02\x00", 0x1000000000001,
    0x10000000000001, "\x0f\x02\x00\x00\x00\x00\x00\x20\x00", 0x10000000000001,
    0x100000000000001LL, "\x0f\x02\x00\x00\x00\x00\x00\x00\x02", 0x100000000000001LL,
    0x1000000000000001LL, "\x0f\x02\x00\x00\x00\x00\x00\x00\x20", 0x1000000000000001LL,
    42, "\x0c\x54", 42,
    500, "\x0d\xe8\x03", 500,
    0xdedbeef, "\x0e\xde\x7d\xdb\x1b", 0xdedbeef,
    0xdeadbeef, "\x0f\xde\x7d\x5b\xbd\x01\x00\x00\x00", 0xdeadbeef,
    0x20000000000000, "\x0f\x00\x00\x00\x00\x00\x00\x40\x00", 0x20000000000000,
    0x123456789abcdef0LL, "\x0f\xe0\xbd\x79\x35\xf1\xac\x68\x24", 0x123456789abcdef0LL,
    -1, "\x01", -1,
    -42, "\x0c\x53", -42,
    -500, "\x0d\xe7\x03", -500,
    -0xdedbeef, "\x0e\xdd\x7d\xdb\x1b", -0xdedbeef,
    -0xdeadbeef, "\x0f\xdd\x7d\x5b\xbd\x01\x00\x00\x00", -0xdeadbeef,
    -0x123456789abcdef0LL, "\x0f\xdf\xbd\x79\x35\xf1\xac\x68\x24", -0x123456789abcdef0LL,
    -- Luajit version also treats cdata integers as integers
    ffi.new("uint8_t", 42), "\x0c\x54", 42,
    ffi.new("int8_t", 42), "\x0c\x54", 42,
    ffi.new("int8_t", -42), "\x0c\x53", -42,
    ffi.new("uint16_t", 42), "\x0c\x54", 42,
    ffi.new("int16_t", 42), "\x0c\x54", 42,
    ffi.new("int16_t", -42), "\x0c\x53", -42,
    ffi.new("uint32_t", 42), "\x0c\x54", 42,
    ffi.new("int32_t", 42), "\x0c\x54", 42,
    ffi.new("int32_t", -42), "\x0c\x53", -42,
    ffi.new("uint64_t", 42), "\x0c\x54", 42,
    ffi.new("int64_t", 42), "\x0c\x54", 42,
    ffi.new("int64_t", -42), "\x0c\x53", -42,

    -- Float
    math.pi, "\x1f\x18\x2d\x44\x54\xfb\x21\x09\x40", math.pi,
    0/0, "\x1f\x00\x00\x00\x00\x00\x00\xf8\xff", 0/0, -- luajit representation of NaN
    1/0, "\x1f\x00\x00\x00\x00\x00\x00\xf0\x7f", 1/0, -- luajit representation of Inf
    -1/0, "\x1f\x00\x00\x00\x00\x00\x00\xf0\xff", -1/0, -- luajit representation of -Inf
    ffi.new("double", math.pi), "\x1f\x18\x2d\x44\x54\xfb\x21\x09\x40", math.pi,
    ffi.new("double", -math.pi), "\x1f\x18\x2d\x44\x54\xfb\x21\x09\xc0", -math.pi,
    ffi.new("float", math.pi), "\x1f\x00\x00\x00\x60\xfb\x21\x09\x40", 3.1415927410126,
    ffi.new("float", -math.pi), "\x1f\x00\x00\x00\x60\xfb\x21\x09\xc0", -3.1415927410126,

    -- Simple
    false, "\x20", false,
    true, "\x21", true,
    nil, "\x22", nil,

    -- Ref
    Zero, "\x30", Zero,
    One, "\x31", One,
    Two, "\x32", Two,
    Three, "\x33", Three,

    -- Tag
    F32Array(4, {math.pi*.5,math.pi,math.pi*1.5,math.pi*2}),
      "\x70" .. -- Tag(0)
        "\x8c\x10".. -- Bytes(16)
          "\xdb\x0f\xc9\x3f\xdb\x0f\x49\x40\xe4\xcb\x96\x40\xdb\x0f\xc9\x40",
    F32Array(4, {math.pi*.5,math.pi,math.pi*1.5,math.pi*2}),

    -- Binary
    -- null terminated C string
    ffi.new("const char*", "Binary!"),
    "\x88Binary!\0",
    Binary(0x42,0x69,0x6e,0x61,0x72,0x79,0x21,0x00),

    -- C byte array
    ffi.new("uint8_t[3]", {1,2,3}),
    "\x83\x01\x02\x03",
    Binary(0x01, 0x02, 0x03),

    -- C double array
    ffi.new("double[1]", {math.pi}),
    "\x88\x18\x2d\x44\x54\xfb\x21\x09\x40",
    Binary(0x18,0x2d,0x44,0x54,0xfb,0x21,0x09,0x40),

    -- String
    "Hello", "\x95Hello", "Hello",

    -- Tuple
    {}, "\xa0", Tuple(),
    {1,2,3}, "\xa3\x02\x04\x06", Tuple(1,2,3),

    -- Map
    {name="Tim"}, "\xb9\x94name\x93Tim", Map("name","Tim"),
    OrderedMap.new(), "\xb0", Map(),
    OrderedMap.new(true,false,1,nil), "\xb4\x21\x20\x02\x22", Map(true,false,1,nil),

    -- Array
    OrderedList.new(1,2,3), "\xc7\x13\x00\x01\x02\x02\x04\x06", OrderedList.new(1,2,3),
    OrderedList.new(), "\xc0", OrderedList.new(),

    -- Complex (uses OrderedMap to preserve map order and nil value)
    { OrderedMap.new(10,100,20,50,true,false), OrderedMap.new("foo",nil) },
    "\xac\x11" .. -- Tuple(17)
        "\xba" .. -- Map(10)
            "\x0c\x14" .. -- Int(20) -> 10
            "\x0c\xc8" .. -- Int(200) -> 100
            "\x0c\x28" .. -- Int(40) -> 20
            "\x0c\x64" .. -- Int(100) -> 50
            "\x21" .. -- Simple(1) -> true
            "\x20" .. -- Simple(0) -> false
            "\xb5" .. -- Map(5)
            "\x93foo" .. -- String(3) "foo"
            "\x22", -- Simple(2) -> null
    { OrderedMap.new(10,100,20,50,true,false), OrderedMap.new("foo",nil) },
}

local function dump_string(str)
    local parts = {}
    for i = 1, #str do
        parts[i] = "\\x" .. tohex(byte(str, i),2)
    end
    return '"' .. concat(parts) .. '"'
end

local function equal(a,b)
    if ((a ~= a) and (b ~= b)) or a == b then return true end
    local kind = type(a)
    if kind == "number" then
        return tostring(a) == tostring(b)
    end
    if kind == "cdata" and nibs.is(a) then
        kind = "table"
    end
    local kindb = type(b)
    if kindb == "cdata" and nibs.is(b) then
        kindb = "table"
    end
    if kind ~= kindb then return false end
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

for i = 1, #tests, 3 do
    print()
    local input = tests[i]
    p("input", input)
    local expected = tests[i+1]
    local expected_output = tests[i+2]
    collectgarbage("collect")
    local buf = nibs:encode(input)
    input = nil
    collectgarbage("collect")
    local str = ffi.string(buf, sizeof(buf))
    collectgarbage("collect")
    print("'expected'\t" .. dump_string(expected))
    collectgarbage("collect")
    print("'actual'\t" .. dump_string(str))
    collectgarbage("collect")
    assert(ffi.string(buf, sizeof(buf)) == expected)
    collectgarbage("collect")
    local decoded = nibs:decode(buf)
    buf = nil
    collectgarbage("collect")
    p("decoded", decoded, "expected", expected_output)
    collectgarbage("collect")
    assert(equal(decoded, expected_output), "decode failed")
    collectgarbage("collect")
end

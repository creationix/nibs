local import = _G.import or require

-- Main types
local ZIGZAG = 0
local FLOAT = 1
local SIMPLE = 2
local REF = 3

local BYTES = 8
local UTF8 = 9
local HEXSTRING = 10
local LIST = 11
local MAP = 12
local ARRAY = 13

local SCOPE = 15

-- Simple subtypes
local FALSE = 0
local TRUE = 1
local NULL = 2

local bit = require 'bit'
local rshift = bit.rshift
local arshift = bit.arshift
local band = bit.band
local lshift = bit.lshift
local bxor = bit.bxor

local ffi = require 'ffi'
local sizeof = ffi.sizeof
local copy = ffi.copy
local ffi_string = ffi.string
local cast = ffi.cast

local insert = table.insert

local NibLib = import "nib-lib"

local U64 = NibLib.U64
local I64 = NibLib.I64

local U8Ptr = NibLib.U8Ptr
local U16Ptr = NibLib.U16Ptr
local U32Ptr = NibLib.U32Ptr
local U64Ptr = NibLib.U64Ptr

local U8Arr = NibLib.U8Arr
local U16Arr = NibLib.U16Arr
local U32Arr = NibLib.U32Arr
local U64Arr = NibLib.U64Arr

local converter = ffi.new 'union {double f;uint64_t i;}'
ffi.cdef [[
    #pragma pack(1)
    struct nibs4 { // for big under 12
        unsigned int big:4; // lower 4 bits are first
        unsigned int small:4;
    };
    #pragma pack(1)
    struct nibs8 { // for big under 256
        uint8_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
    #pragma pack(1)
    struct nibs16 { // for big under 256
        uint16_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
    #pragma pack(1)
    struct nibs32 { // for big under 256
        uint32_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
    #pragma pack(1)
    struct nibs64 { // for big under 256
        uint64_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
]]


local nibs4 = ffi.typeof 'struct nibs4'
local nibs8 = ffi.typeof 'struct nibs8'
local nibs16 = ffi.typeof 'struct nibs16'
local nibs32 = ffi.typeof 'struct nibs32'
local nibs64 = ffi.typeof 'struct nibs64'
local nibs4ptr = ffi.typeof 'struct nibs4*'
local nibs8ptr = ffi.typeof 'struct nibs8*'
local nibs16ptr = ffi.typeof 'struct nibs16*'
local nibs32ptr = ffi.typeof 'struct nibs32*'
local nibs64ptr = ffi.typeof 'struct nibs64*'

---Encode a small/big pair into binary parts
---@param small integer any 4-bit unsigned integer
---@param big integer and 64-bit unsigned integer
---@return integer size of encoded bytes
---@return ffi.cdata* bytes as nibs struct
local function encode_pair(small, big)
    if big < 0xc then
        return 1, nibs4(big, small)
    elseif big < 0x100 then
        return 2, nibs8(big, 12, small)
    elseif big < 0x10000 then
        return 3, nibs16(big, 13, small)
    elseif big < 0x100000000 then
        return 5, nibs32(big, 14, small)
    else
        return 9, nibs64(big, 15, small)
    end
end

--- Convert a signed 64 bit integer to an unsigned 64 bit integer using zigzag encoding
---@param num integer
---@return integer
local function encode_zigzag(num)
    local i = I64(num)
    return U64(bxor(arshift(i, 63), lshift(i, 1)))
end

---@param val number
---@return integer
local function encode_float(val)
    -- Use same NaN encoding as used by V8 JavaScript engine
    if val ~= val then
        return 0x7ff8000000000000ULL
    end
    converter.f = val
    return converter.i
end

---Combine binary parts into a single binary string
---@param size integer total number of expected bytes
---@param parts any parts to combine
---@return number size
---@return ffi.cdata* buffer
local function combine(size, parts)
    ---@type ffi.cdata*
    local buf = U8Arr(size)
    local offset = 0
    local function write(part)
        local t = type(part)
        if t == "number" then
            buf[offset] = part
            offset = offset + 1
        elseif t == "string" then
            local len = #part
            copy(buf + offset, part, len)
            offset = offset + len
        elseif t == "cdata" then
            local len = assert(sizeof(part))
            copy(buf + offset, part, len)
            offset = offset + len
        elseif t == "table" then
            for _, p in ipairs(part) do
                write(p)
            end
        else
            error("bad type in parts")
        end
    end

    write(parts)
    assert(offset == size)
    return size, buf
end

local encode_any
local encode_list
local encode_map
local encode_array
local generate_array_index
local encode_scope

---@class Nibs
local Nibs = {}

--- A value that can be serialized with nibs
---@alias Value ffi.cdata* | string | number | boolean | nil | Scope | Ref | table<Value,Value>

---Encode any value into a nibs encoded binary string
---@param val Value
---@return string
function Nibs.encode(val)
    local size, encoded = combine(encode_any(val))
    return ffi_string(encoded, size)
end

---@param val any
---@return integer size of encoded bytes
---@return any bytes as parts
function encode_any(val)
    local t = type(val)
    if t == "number" then
        if NibLib.isWhole(val) then
            return encode_pair(ZIGZAG, encode_zigzag(val))
        else
            return encode_pair(FLOAT, encode_float(val))
        end
    elseif t == "string" then
        local len = #val
        if len % 2 == 0 and string.match(val, "^[0-9a-f]+$") then
            len = len / 2
            local size, head = encode_pair(HEXSTRING, len)
            return size + len, { NibLib.hexStrToBuf(val), head  }
        end
        local size, head = encode_pair(UTF8, len)
        return size + len, { val, head }
    elseif t == "cdata" then
        if NibLib.isInteger(val) then
            -- Treat cdata integers as integers
            return encode_pair(ZIGZAG, encode_zigzag(val))
        elseif NibLib.isFloat(val) then
            -- Treat cdata floats as floats
            return encode_pair(FLOAT, encode_float(val))
        else
            collectgarbage("collect")
            local len = assert(sizeof(val))
            collectgarbage("collect")
            local size, head = encode_pair(BYTES, len)
            collectgarbage("collect")
            if len > 0 then
                return size + len, { val, head }
            else
                return size, head
            end
        end
    elseif t == "boolean" then
        return encode_pair(SIMPLE, val and TRUE or FALSE)
    elseif t == "nil" then
        return encode_pair(SIMPLE, NULL)
    elseif t == "table" then
        local mt = getmetatable(val)
        if mt == Ref then
            return encode_pair(REF, val[1])
        elseif mt == Scope then
            return encode_scope(val)
        elseif NibLib.isArrayLike(val) then
            if mt and mt.__is_indexed then
                return encode_array(val)
            end
            return encode_list(val)
        else
            return encode_map(val)
        end
    else
        return encode_any(tostring(val))
    end
end

---@param list Value[]
---@return integer
---@return any
function encode_list(list)
    local total = 0
    local body = {}
    for i, v in ipairs(list) do
        local size, entry = encode_any(v)
        body[i] = entry
        total = total + size
    end
    local size, head = encode_pair(LIST, total)
    return size + total, { body, head }
end

---@param list Value[]
---@return integer
---@return any
function encode_array(list)
    local total = 0
    local body = {}
    local offsets = {}
    for i, v in ipairs(list) do
        local size, entry = encode_any(v)
        body[i] = entry
        total = total + size
        offsets[i] = total - 1
    end
    local more, index = generate_array_index(offsets)
    total = total + more
    local size, head = encode_pair(ARRAY, total)
    return size + total, { body, index, head }
end

---@param scope Scope
---@return integer
---@return any
function encode_scope(scope)
    local total = 0

    -- first encode the refs and record their relative offsets
    local body = {}
    local offsets = {}
    for i = 1, #scope - 1 do
        local v = scope[i]
        local size, entry = encode_any(v)
        body[i] = entry
        total = total + size
        offsets[i] = total - 1
    end

    -- Generate index header and value header
    local more, index = generate_array_index(offsets)
    total = total + more

    -- Then encode the wrapped value
    local valueSize, valueEntry = encode_any(scope[#scope])
    total = total + valueSize

    -- combine everything
    local size, head = encode_pair(SCOPE, total)
    return size + total, { body, index, valueEntry, head }
end

---@param map table<Value,Value>
---@return integer
---@return any
function encode_map(map)
    local total = 0
    local body = {}
    for k, v in pairs(map) do
        local size, entry = combine(encode_any(k))
        insert(body, entry)
        total = total + size
        size, entry = encode_any(v)
        insert(body, entry)
        total = total + size
    end
    local size, head = encode_pair(MAP, total)
    return size + total, { body, head }
end

---@private
---@param offsets integer[]
---@return number
---@return any
function generate_array_index(offsets)
    local last = 0
    local count = #offsets
    if count > 0 then
        last = offsets[count]
    end
    local index, width
    if last < 0x100 then
        width = 1
        index = U8Arr(count, offsets)
    elseif last < 0x10000 then
        width = 2
        index = U16Arr(count, offsets)
    elseif last < 0x100000000 then
        width = 4
        index = U32Arr(count, offsets)
    else
        width = 8
        index = U64Arr(count, offsets)
    end
    local more, head = encode_pair(width, count)
    return more + sizeof(index), { index, head }
end

--- Convert an I64 to a normal number if it's in the safe range
---@param n integer cdata I64
---@return integer|number maybeNum
local function tonumberMaybe(n)
    return (n <= 0x1fffffffffffff and n >= -0x1fffffffffffff)
        and tonumber(n)
        or n
end

---@param data integer[] U8Arr reverse nibs serialized binary data
---@param offset integer 0 based offset into U8Arr
---@return integer offset after decoding
---@return integer little type or width
---@return integer big value or count or size
local function decode_pair(data, offset)
    p("decode pair", offset)
    local byte = data[offset - 1]
    local little = rshift(byte, 4)
    local big = band(byte, 0xf)
    if big < 12 then
        p { bits = 4, little = little, big = big, offset = offset }
        return offset - 1, little, big
    elseif big == 12 then
        big = cast(U8Ptr, data + offset - 2)[0]
        p { bits = 8, little = little, big = big, offset = offset }
        return offset - 2, little, big
    elseif big == 13 then
        big = cast(U16Ptr, data + offset - 3)[0]
        p { bits = 16, little = little, big = big, offset = offset }
        return offset - 3, little, big
    elseif big == 14 then
        big = cast(U32Ptr, data + offset - 5)[0]
        p { bits = 32, little = little, big = big, offset = offset }
        return offset - 5, little, big
    else
        big = cast(U64Ptr, data + offset - 9)[0]
        p { bits = 64, little = little, big = big, offset = offset }
        return offset - 9, little, big
    end
end

---@param data integer[]
---@param width integer
---@param offset integer
---@return integer
local function decode_pointer(data, width, offset)
    p("decode pointer", { offset = offset, width = width })
    if width == 1 then
        return data[offset]
    else
        error "TODO: decode bigger pointers"
    end
end

---Convert an unsigned 64 bit integer to a signed 64 bit integer using zigzag decoding
---@param num integer
---@return integer
local function decode_zigzag(num)
    local i = I64(num)
    local o = bxor(rshift(i, 1), -band(i, 1))
    return tonumberMaybe(o)
end

--- Convert an unsigned 64 bit integer to a double precision floating point by casting the bits
---@param val integer
---@return number
local function decode_float(val)
    p("decode_float", val)
    converter.i = val
    return converter.f
end

---@param data integer[]
---@param length integer
---@return string
local function to_hex(data, length)
    local parts = {}
    local i = 0
    while i < length do
        local b = data[i]
        i = i + 1
        parts[i] = bit.tohex(b, 2)
    end
    return table.concat(parts, ' ')
end

local function decode_bytes(data, offset, big)
    p("decode_bytes", { offset = offset, big = big })
    local buf = U8Arr(big)
    copy(buf, data + offset - big, big)
    return buf
end

local function decode_utf8(data, offset, big)
    p("decode_utf8", { offset = offset, big = big })
    return ffi_string(data + offset - big, big)
end

local function tohexcode(b)
    return b + (b < 10 and 0x30 or 0x57)
end

local function decode_hexstring(data, offset, big)
    p("decode_hexstring", { offset = offset, big = big })
    local buf = U8Arr(big * 2)
    local ptr = data + offset - big
    for i = 0, big - 1 do
        local b = ptr[i]
        buf[i * 2] = tohexcode(rshift(b, 4))
        buf[i * 2 + 1] = tohexcode(band(b, 15))
    end
    return ffi_string(buf, big * 2)
end

--- Reverse a list in-place
---@param list any[]
local function reverse(list)
    local len = #list
    for i = 1, rshift(len, 1) do
        local j = len - i + 1
        list[j], list[i] = list[i], list[j]
    end
end

local function Symbol(name)
    return setmetatable({}, {
        __name = name,
        __tostring = function() return "$" .. name end,
    })
end

local DATA = Symbol "DATA"
local OFFSETS = Symbol "OFFSETS"
local KEYS = Symbol "KEYS"
local FIRST = Symbol "FIRST"
local LAST = Symbol "LAST"
local SCOPE_OFFSET = Symbol "SCOPE_OFFSET"
local WIDTH = Symbol "WIDTH"
local COUNT = Symbol "COUNT"
local INDEX_FIRST = Symbol "INDEX_FIRST"

--- Skip a value
---@param data integer[] U8Arr
---@param offset integer 0 based offset into data pointing to final byte of value
---@return integer new offset into next value
local function skip_value(data, offset)
    p("skip", { offset = offset })
    local o, l, b = decode_pair(data, offset)
    if l < 8 then
        -- inline values are done after parsing the nibs pair
        return o
    else
        -- container values also need the contents skipped
        return o - b
    end
end

---@alias Nibs.Value boolean|number|string|ffi.cdata*|Nibs.List|Nibs.Array|Nibs.Map|nil

local decode

---@param data integer[]
---@param id integer
---@param scope_offset integer
---@return Nibs.Value
local function decode_ref(data, id, scope_offset)
    p("decode_ref", { id = id, scope_offset = scope_offset })
    local offset, _, big = decode_pair(data, scope_offset)
    local first = offset - big
    offset = skip_value(data, offset)
    local o, w, c = decode_pair(data, offset)
    local width = w
    local index_first = o - w * c
    p { index_first = index_first, count = count, w = w }

    local ptr = decode_pointer(data, width, index_first + width * id)
    p{ptr=ptr}
    return decode(data, first + ptr, scope_offset)
end

---@class Nibs.List
Nibs.List = { __name = "Nibs.List", __is_array_like = true }

function Nibs.List:__len()
    ---@type integer[]|nil array of offsets to last header byte of each value
    local offsets = rawget(self, OFFSETS)
    if not offsets then
        ---@type integer[]  data
        local data = rawget(self, DATA)
        ---@type integer offset at end of value list
        local last = rawget(self, LAST)
        ---@type integer offset of start value list
        local first = rawget(self, FIRST)
        --- Current offset to read from
        local offset = last
        offsets = {}
        while offset > first do
            offsets[#offsets + 1] = offset
            offset = skip_value(data, offset)
        end
        reverse(offsets)
        rawset(self, OFFSETS, offsets)
    end
    return #offsets
end

function Nibs.List:__index(key)
    assert(#self)
    ---@type integer[]
    local offsets = rawget(self, OFFSETS)
    local data = rawget(self, DATA)
    local scope_offset = rawget(self, SCOPE_OFFSET)
    local offset = offsets[key]
    if not offset then return end
    local value = decode(data, offset, scope_offset)
    rawset(self, key, value)
    return value
end

function Nibs.List:__ipairs()
    local i = 0
    local len = #self
    return function()
        if i >= len then return end
        i = i + 1
        return i, self[i]
    end
end

Nibs.List.__pairs = Nibs.List.__ipairs

---@class Nibs.Array
Nibs.Array = { __name = "Nibs.Array", __is_array_like = true, __is_indexed = true }

function Nibs.Array:__len()
    ---@type integer
    local count = rawget(self, COUNT)
    if not count then
        ---@type integer[]
        local data = rawget(self, DATA)
        ---@type integer
        local last = rawget(self, LAST)
        -- Read the array index header
        local o, w, c = decode_pair(data, last)
        rawset(self, WIDTH, w)
        rawset(self, INDEX_FIRST, o - w * c + 1)
        count = c
        rawset(self, COUNT, count)
    end
    return count
end

function Nibs.Array:__index(k)
    local count = #self
    if type(k) ~= "number" or math.floor(k) ~= k or k < 1 or k > count then return end
    --- @type integer[] reverse nibs encoded binary data
    local data = rawget(self, DATA)
    --- @type integer offset to start of index
    local index_first = rawget(self, INDEX_FIRST)
    --- @type integer width of index pointers
    local width = rawget(self, WIDTH)
    local offset = decode_pointer(data, width, index_first + width * (k - 1))
    local first = rawget(self, FIRST)
    local scope_offset = rawget(self, SCOPE_OFFSET)
    local v = decode(data, first + offset, scope_offset)
    rawset(self, k, v)
    return v
end

function Nibs.Array:__ipairs()
    local i = 0
    local len = #self
    return function()
        if i >= len then return end
        i = i + 1
        return i, self[i]
    end
end

---@class Nibs.Map
Nibs.Map = { __name = "Nibs.Map", __is_array_like = false }

function Nibs.Map:__len()
    ---@type table<any,integer>|nil array of offsets to last header byte of each value
    local offsets = rawget(self, OFFSETS)
    if not offsets then
        ---@type integer[]  data
        local data = rawget(self, DATA)
        ---@type integer offset at end of value list
        local last = rawget(self, LAST)
        ---@type integer offset of start value list
        local first = rawget(self, FIRST)
        ---@type integer|nil scope index
        local scope_offset = rawget(self, SCOPE_OFFSET)
        --- Current offset to read from
        local offset = last
        ---@type any[]
        local keys = {}
        offsets = {}
        while offset > first do
            local o = offset
            offset = skip_value(data, offset)
            ---@type any
            local key = decode(data, offset, scope_offset)
            assert(key ~= nil)
            keys[#keys + 1] = key
            offsets[key] = o
            -- TODO: we shouldn't need this skip, we should get offset from decode
            offset = skip_value(data, offset)
        end
        reverse(keys)
        rawset(self, KEYS, keys)
        rawset(self, OFFSETS, offsets)
    end
    return 0
end

function Nibs.Map:__pairs()
    assert(#self)
    ---@type integer[]
    local data = rawget(self, DATA)
    ---@type table<any,integer>
    local offsets = rawget(self, OFFSETS)
    ---@type any[]
    local keys = rawget(self, KEYS)
    ---@type integer|nil
    local scope_offset = rawget(self, SCOPE_OFFSET)
    local i = 0
    local len = #keys
    return function ()
        if i < len then
            i = i + 1
            local key = keys[i]
            local offset = offsets[key]
            local value = decode(data, offset, scope_offset)
            return key, value
        end
    end
end

function Nibs.Map.__ipairs()
    return function () end
end

function Nibs.Map:__index(key)
    assert(#self)
    ---@type integer[]
    local data = rawget(self, DATA)
    ---@type table<any,integer>
    local offsets = rawget(self, OFFSETS)
    ---@type integer|nil
    local scope_offset = rawget(self, SCOPE_OFFSET)
    local offset = offsets[key]
    if not offset then return end
    -- TODO: consider memoizing this
    local value = decode(data, offset, scope_offset)
    return value
end

--- Mount a nibs binary value for lazy reading
--- when accessing properties on maps, lists, and arrays, the value
--- is decoded on the fly and memoized for faster access.
--- @param data string|integer[] binary reverse nibs encoded value
--- @param length integer|nil length of binary data
--- @param scope_offset integer|nil scope to use for references
--- @return Nibs.Value
function Nibs.decode(data, length, scope_offset)
    if type(data) == "string" then
        if not length then length = #data end
        ---@type integer[]
        local buf = U8Arr(length)
        copy(buf, data, length)
        data = buf
    end
    assert(length, "unknown value end")
    print(string.format("decode %s", to_hex(data, length)))
    local offset = length
    local little, big
    offset, little, big = decode_pair(data, offset)
    if little == ZIGZAG then
        return decode_zigzag(big)
    elseif little == FLOAT then
        return decode_float(big)
    elseif little == SIMPLE then
        if big == FALSE then
            return false
        elseif big == TRUE then
            return true
        elseif big == NULL then
            return nil
        else
            error(string.format("Unknown SIMPLE %d", big))
        end
    elseif little == REF then
        assert(scope_offset, "missing scope index")
        return decode_ref(data, big, scope_offset)
    elseif little == BYTES then
        return decode_bytes(data, offset, big)
    elseif little == UTF8 then
        return decode_utf8(data, offset, big)
    elseif little == HEXSTRING then
        return decode_hexstring(data, offset, big)
    elseif little == LIST then
        return setmetatable({
            [DATA] = data,
            [FIRST] = offset - big,
            [LAST] = offset,
            [SCOPE_OFFSET] = scope_offset,
        }, Nibs.List)
    elseif little == MAP then
        return setmetatable({
            [DATA] = data,
            [FIRST] = offset - big,
            [LAST] = offset,
            [SCOPE_OFFSET] = scope_offset,
        }, Nibs.Map)
    elseif little == ARRAY then
        return setmetatable({
            [DATA] = data,
            [FIRST] = offset - big,
            [LAST] = offset,
            [SCOPE_OFFSET] = scope_offset,
        }, Nibs.Array)
    elseif little == SCOPE then
        return decode(data, offset, length)
    else
        error(string.format("Unknown type 0x%x", little))
    end
end
decode = Nibs.decode

return Nibs

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
            return size + len, { NibLib.hexStrToBuf(val), head }
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
        if mt and mt.__is_ref then
            return encode_pair(REF, val[1])
        elseif mt and mt.__is_scope then
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
        offsets[i] = total
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
        offsets[i] = total
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
    converter.i = val
    return converter.f
end

local function Symbol(name)
    return setmetatable({}, {
        __name = name,
        __tostring = function() return "$" .. name end,
    })
end

-- Reference to array buffer so it stays alive
local DATA = Symbol "DATA"
-- pointer before values (as integer data offset)
local START = Symbol "START"
-- pointer after values (as integer data offset) (also start of index array when present)
local END = Symbol "END"

-- pointer width of array index
local WIDTH = Symbol "WIDTH"
-- pointer count of array index
local COUNT = Symbol "COUNT"

-- Array of offsets for list and map
local OFFSETS = Symbol "OFFSETS"

-- Reference to the nearest scope array
local CURRENT_SCOPE = Symbol "CURRENT_SCOPE"

---@alias Nibs.Value boolean|number|string|integer[]|Nibs.List|Nibs.Array|Nibs.Map|nil

---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@return integer[] new_last after consuming header
---@return integer little type or width
---@return integer big value or count or size
local function decode_pair(first, last)
    last = last - 1
    assert(last >= first)
    local byte = last[0]
    local little = rshift(byte, 4)
    local big = band(byte, 0xf)
    p(little,big)
    if big < 12 then
        return last, little, big
    elseif big == 12 then
        last = last - 1
        assert(last >= first)
        return last, little, cast(U8Ptr, last)[0]
    elseif big == 13 then
        last = last - 2
        assert(last >= first)
        return last, little, cast(U16Ptr, last)[0]
    elseif big == 14 then
        last = last - 4
        assert(last >= first)
        return last, little, cast(U32Ptr, last)[0]
    else
        last = last - 8
        assert(last >= first)
        return last, little, cast(U64Ptr, last)[0]
    end
end

---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@return integer[] new_last after consuming header
---@return integer[] bytes decoded value
local function decode_bytes(first, last)
    local len = last - first
    local buf = U8Arr(len)
    copy(buf, first, len)
    return first, buf
end

---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@return integer[] new_last after consuming header
---@return string utf8 decoded value
local function decode_utf8(first, last)
    return first, ffi_string(first, last - first)
end

---@param b integer nibble value
---@return integer ascii hex code
local function tohexcode(b)
    return b + (b < 10 and 0x30 or 0x57)
end

---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@return integer[] new_last after consuming header
---@return string hex decoded value
local function decode_hexstring(first, last)
    local len = last - first
    local buf = U8Arr(len * 2)
    for i = 0, len - 1 do
        local b = first[i]
        buf[i * 2] = tohexcode(rshift(b, 4))
        buf[i * 2 + 1] = tohexcode(band(b, 15))
    end
    return first, ffi_string(buf, len * 2)
end

local decode_list, decode_map, decode_array, decode_scope

---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@return integer[] new_last after consuming value
local function skip_value(first, last)
    local n, l, b = decode_pair(first, last)
    last = l < 8 and n or n - b
    assert(last >= first)
    return last
end

---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@param data integer[] original buffer (for gc ref)
---@param scope? Nibs.Array nearest nibs scope array
---@return integer[] new_last after consuming value
---@return Nibs.Value decoded_value
local function decode_value(first, last, data, scope)
    p("decode_value", first,last,scope)
    assert(last > first)

    -- Read the value header and update the upper boundary
    local type_tag, int_val
    do
        local new_last
        new_last, type_tag, int_val = decode_pair(first, last)
        assert(new_last >= first)
        last = new_last
    end

    -- Process inline types (0-7)
    if type_tag == ZIGZAG then
        return last, decode_zigzag(int_val)
    elseif type_tag == FLOAT then
        return last, decode_float(int_val)
    elseif type_tag == SIMPLE then
        if int_val == FALSE then
            return last, false
        elseif int_val == TRUE then
            return last, true
        elseif int_val == NULL then
            return last, nil
        else
            error(string.format("Unknown SIMPLE %d", int_val))
        end
    elseif type_tag == REF then
        assert(scope, "missing scope array")
        return last, scope[int_val + 1]
    elseif type_tag < 8 then
        error(string.format("Unknown inline type %d", type_tag))
    end

    -- Use the length prefix to tighten up the lower boundary
    do
        local new_first = last - int_val
        assert(new_first >= first)
        first = new_first
    end

    if type_tag == BYTES then
        return decode_bytes(first, last)
    elseif type_tag == UTF8 then
        return decode_utf8(first, last)
    elseif type_tag == HEXSTRING then
        return decode_hexstring(first, last)
    elseif type_tag == LIST then
        return decode_list(first, last, data, scope)
    elseif type_tag == MAP then
        return decode_map(first, last, data, scope)
    elseif type_tag == ARRAY then
        return decode_array(first, last, data, scope)
    elseif type_tag == SCOPE then
        return decode_scope(first, last, data, scope)
    else
        error(string.format("Unknown container type %d", type_tag))
    end
end

function decode_list(first, last, data, scope)
    return first, setmetatable({
        [START] = first,
        [END] = last,
        [DATA] = data,
        [CURRENT_SCOPE] = scope,
    }, Nibs.List)
end

function decode_map(first, last, data, scope)
    return first, setmetatable({
        [START] = first,
        [END] = last,
        [DATA] = data,
        [CURRENT_SCOPE] = scope,
    }, Nibs.Map)
end

function decode_array(first, last, data, scope)
    local n, l, b = decode_pair(first, last)
    return first, setmetatable({
        [START] = first,
        [END] = n - l * b,
        [WIDTH] = l,
        [COUNT] = b,
        [DATA] = data,
        [CURRENT_SCOPE] = scope,
    }, Nibs.Array)
end

function decode_scope(first, last, data, scope)
    local index = skip_value(first, last)
    assert(index >= first)
    local _, value
    _, scope = decode_array(first, index, data, scope)
    _, value = decode_value(index, last, data, scope)
    return first, value
end

-- Reverse a list in place
---@param list any[]
local function reverse(list)
    local len = #list
    for i = 1, rshift(len, 1) do
        local j = len - i + 1
        list[i], list[j] = list[j], list[i]
    end
end

---@param self Nibs.List|Nibs.Map
local function get_offsets(self)
    ---@type integer[][]
    local offsets = rawget(self, OFFSETS)
    if not offsets then
        ---@type integer[]
        local first = rawget(self, START)
        ---@type integer[]
        local last = rawget(self, END)
        local i = 0
        offsets = {}
        while last > first do
            i = i + 1
            offsets[i] = last
            last = skip_value(first, last)
        end
        assert(last == first)
        reverse(offsets)
        offsets[0] = first
        rawset(self, OFFSETS, offsets)
    end
    return offsets
end

---@class Nibs.List
Nibs.List = { __name = "Nibs.List", __is_array_like = true }

function Nibs.List:__len()
    return #get_offsets(self)
end

function Nibs.List:__index(key)
    if type(key) ~= "number" or math.floor(key) ~= key or key < 1 then return end
    ---@type integer[][]
    local offsets = get_offsets(self)
    if key > #offsets then return end
    ---@type integer[]
    local first = offsets[key - 1]
    local last = offsets[key]
    ---@type integer[]
    local data = rawget(self, DATA)
    ---@type Nibs.Array|nil
    local scope = rawget(self, CURRENT_SCOPE)
    local _, value = decode_value(first, last, data, scope)
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

---@class Nibs.Map
Nibs.Map = { __name = "Nibs.Map", __is_array_like = false }

function Nibs.Map.__len()
    return 0
end

function Nibs.Map:__pairs()
    local offsets = get_offsets(self)
    local i = 0
    local data = rawget(self, DATA)
    local scope = rawget(self, CURRENT_SCOPE)
    return function()
        if i >= #offsets then return end
        i = i + 2
        local first = offsets[i - 2]
        local mid = offsets[i - 1]
        local last = offsets[i]
        assert(i and first and mid and last)
        p(offsets)
        local _, key = decode_value(first, mid, data, scope)
        local _, value = decode_value(mid, last, data, scope)
        rawset(self, key, value)
        return key, value
    end
end

function Nibs.Map.__ipairs()
    return function() end
end

function Nibs.Map:__index(key)
    local offsets = get_offsets(self)
    local data = rawget(self, DATA)
    local scope = rawget(self, CURRENT_SCOPE)
    for i = 0, #offsets - 1, 2 do
        local first = offsets[i]
        local mid = offsets[i + 1]
        local _, k = decode_value(first, mid, data, scope)
        if k == key then
            local last = offsets[i + 2]
            local _, value = decode_value(mid, last, data, scope)
            rawset(self, key, value)
            return value
        end
    end
end

---@class Nibs.Array
Nibs.Array = { __name = "Nibs.Array", __is_array_like = true, __is_indexed = true }

function Nibs.Array:__len()
    ---@type integer
    local count = rawget(self, COUNT)
    return count
end

function Nibs.Array:__index(k)
    ---@type integer
    local count = rawget(self, COUNT)
    if type(k) ~= "number" or math.floor(k) ~= k or k < 1 or k > count then return end
    ---@type integer
    local width = rawget(self, WIDTH)
    ---@type integer[] start of value
    local first = rawget(self, START)
    ---@type integer[] end of value, start of index
    local last = rawget(self, END)
    ---@type ffi.ctype*
    local Ptr = assert(width == 1 and U8Ptr
        or width == 2 and U16Ptr
        or width == 4 and U32Ptr
        or width == 8 and U64Ptr
        or nil, "invalid width")
    ---@type integer
    local offset = cast(Ptr, last + (k - 1) * width)[0]
    ---@type integer[]
    local data = rawget(self, DATA)
    ---@type Nibs.Array|nil
    local scope = rawget(self, CURRENT_SCOPE)
    local _, value = decode_value(first, first + offset, data, scope)
    rawset(self, k, value)
    return value
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

--- @param data string|integer[] binary reverse nibs encoded value
--- @param length? integer length of binary data
function Nibs.decode(data, length)
    if type(data) == "string" then
        length = length or #data
        local buf = U8Arr(length)
        copy(buf, data, length)
        data = buf
    end
    assert(length, "unknown length")
    assert(length > 0, "empty data")
    local offset, value = decode_value(data, data + length, data)
    assert(offset - data == 0)
    return value
end

return Nibs

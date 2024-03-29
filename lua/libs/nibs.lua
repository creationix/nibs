local import = _G.import or require

local HamtIndex = import "hamt-index"

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
local TRIE = 14
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

local Tibs = import 'tibs'
local List = Tibs.List
local Map = Tibs.Map
local Array = Tibs.Array
local Trie = Tibs.Trie
local Ref = Tibs.Ref
local Scope = Tibs.Scope

local NibLib = import "nib-lib"

local NibsList, NibsMap, NibsArray, NibsTrie

local U64 = NibLib.U64
local I64 = NibLib.I64

local U8Ptr = NibLib.U8Ptr
local U16Ptr = NibLib.U16Ptr
local U32Ptr = NibLib.U32Ptr
local U64Ptr = NibLib.U64Ptr

local Slice8 = NibLib.U8Arr
local Slice16 = NibLib.U16Arr
local Slice32 = NibLib.U32Arr
local Slice64 = NibLib.U64Arr

local converter = ffi.new 'union {double f;uint64_t i;}'
ffi.cdef [[
    #pragma pack(1)
    struct nibs4 { // for big under 12
        unsigned int big:4; // lower 4 bits are first
        unsigned int small:4;
    };
    #pragma pack(1)
    struct nibs8 { // for big under 256
        unsigned int prefix:4;
        unsigned int small:4;
        uint8_t big;
    };
    #pragma pack(1)
    struct nibs16 { // for big under 256
        unsigned int prefix:4;
        unsigned int small:4;
        uint16_t big;
    };
    #pragma pack(1)
    struct nibs32 { // for big under 256
        unsigned int prefix:4;
        unsigned int small:4;
        uint32_t big;
    };
    #pragma pack(1)
    struct nibs64 { // for big under 256
        unsigned int prefix:4;
        unsigned int small:4;
        uint64_t big;
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
        return 2, nibs8(12, small, big)
    elseif big < 0x10000 then
        return 3, nibs16(13, small, big)
    elseif big < 0x100000000 then
        return 5, nibs32(14, small, big)
    else
        return 9, nibs64(15, small, big)
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
    local buf = Slice8(size)
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
local encode_trie
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
            return size + len, { head, NibLib.hexStrToBuf(val) }
        end
        local size, head = encode_pair(UTF8, len)
        return size + len, { head, val }
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
                return size + len, { head, val }
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
            if mt and mt.__is_indexed then
                collectgarbage("collect")
                return encode_trie(val)
            end
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
    local size, prefix = encode_pair(LIST, total)
    return size + total, { prefix, body }
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
        offsets[i] = total
        total = total + size
    end
    local more, index = generate_array_index(offsets)
    total = total + more
    local size, prefix = encode_pair(ARRAY, total)
    return size + total, { prefix, index, body }
end

---@param scope Scope
---@return integer
---@return any
function encode_scope(scope)
    local total = 0

    -- First encode the wrapped value
    local valueSize, valueEntry = encode_any(scope[1])

    -- Then encode the refs and record their relative offsets
    local body = {}
    local offsets = {}
    for i = 2, #scope do
        local v = scope[i]
        local size, entry = encode_any(v)
        body[i - 1] = entry
        offsets[i - 1] = total
        total = total + size
    end

    -- Generate index header and value header
    local more, index = generate_array_index(offsets)
    total = total + more + valueSize

    -- combine everything
    local size, prefix = encode_pair(SCOPE, total)
    return size + total, { prefix, valueEntry, index, body }
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
    return size + total, { head, body }
end

---@param map table<Value,Value>
---@return integer
---@return any
function encode_trie(map)
    local total = 0
    local body = {}
    local offsets = {}
    for k, v in pairs(map) do
        collectgarbage("collect")

        local size, entry = combine(encode_any(k))
        offsets[entry] = total
        insert(body, entry)
        total = total + size

        size, entry = encode_any(v)
        insert(body, entry)
        total = total + size
    end

    local count, width, index = HamtIndex.encode(offsets)
    total = total + count * width

    local size, prefix, meta
    size, meta = encode_pair(width, count)
    total = total + size

    size, prefix = encode_pair(TRIE, total)

    return total + size, { prefix, meta, index, body }
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
        index = Slice8(count, offsets)
    elseif last < 0x10000 then
        width = 2
        index = Slice16(count, offsets)
    elseif last < 0x100000000 then
        width = 4
        index = Slice32(count, offsets)
    else
        width = 8
        index = Slice64(count, offsets)
    end
    local more, head = encode_pair(width, count)
    return more + sizeof(index), { head, index }
end

---@param read ByteProvider
---@param offset number
---@return number
---@return number
---@return number
local function decode_pair(read, offset)
    local data = read(assert(tonumber(offset)), 9)
    local pair = cast(nibs4ptr, data)
    ---@cast pair {big:integer,small:integer}
    if pair.big == 12 then
        pair = cast(nibs8ptr, data)
        ---@cast pair {prefix:integer,small:integer,big:integer}
        return offset + 2, pair.small, pair.big
    elseif pair.big == 13 then
        pair = cast(nibs16ptr, data)
        ---@cast pair {prefix:integer,small:integer,big:integer}
        return offset + 3, pair.small, pair.big
    elseif pair.big == 14 then
        pair = cast(nibs32ptr, data)
        ---@cast pair {prefix:integer,small:integer,big:integer}
        return offset + 5, pair.small, pair.big
    elseif pair.big == 15 then
        pair = cast(nibs64ptr, data)
        ---@cast pair {prefix:integer,small:integer,big:integer}
        return offset + 9, pair.small, pair.big
    else
        return offset + 1, pair.small, pair.big
    end
end

---Convert an unsigned 64 bit integer to a signed 64 bit integer using zigzag decoding
---@param num integer
---@return integer
local function decode_zigzag(num)
    local i = I64(num)
    local o = bxor(rshift(i, 1), -band(i, 1))
    return NibLib.tonumberMaybe(o)
end

--- Convert an unsigned 64 bit integer to a double precision floating point by casting the bits
---@param val number
---@return integer
local function decode_float(val)
    converter.i = val
    return converter.f
end

local function decode_simple(big)
    if big == FALSE then
        return false
    elseif big == TRUE then
        return true
    elseif big == NULL then
        return nil
    end
    error(string.format("Invalid simple type %d", big))
end

---@param read ByteProvider
---@param offset number
---@param length number
---@return ffi.ctype*
local function decode_bytes(read, offset, length)
    return NibLib.strToBuf(read(offset, length))
end

---@param read ByteProvider
---@param offset number
---@param length number
---@return string
local function decode_string(read, offset, length)
    return read(offset, length)
end

---@param read ByteProvider
---@param offset number
---@param length number
---@return string
local function decode_hexstring(read, offset, length)
    return NibLib.strToHexStr(read(offset, length))
end

local function decode_pointer(read, offset, width)
    local str = read(offset, width)
    if width == 1 then return cast(U8Ptr, str)[0] end
    if width == 2 then return cast(U16Ptr, str)[0] end
    if width == 4 then return cast(U32Ptr, str)[0] end
    if width == 8 then return cast(U64Ptr, str)[0] end
    error("Illegal pointer width " .. width)
end

local function skip(read, offset)
    local little, big
    offset, little, big = decode_pair(read, offset)
    if little < 8 then
        return offset
    else
        return offset + big
    end
end

local get

---@class NibsMetaEntry
---@field read ByteProvider
---@field scope DecodeScope? optional ref scope chain
---@field alpha number start of data as offset
---@field omega number end of data as offset to after data
---@field width number? width of index entries
---@field count number? count of index entries
---@field seed number? hash seed for trie hamt

-- Weakmap for associating private metadata to tables.
---@type table<table,NibsMetaEntry>
local NibsMeta = setmetatable({}, { __mode = "k" })

---@class NibsList
NibsList = {}
NibsList.__name = "NibsList"
NibsList.__is_array_like = true

---@param read ByteProvider
---@param offset number
---@param length number
---@param scope DecodeScope?
---@return NibsList
function NibsList.new(read, offset, length, scope)
    local self = setmetatable({}, NibsList)
    NibsMeta[self] = {
        read = read,
        scope = scope,
        alpha = offset,          -- Start of list values
        omega = offset + length, -- End of list values
    }
    return self
end

function NibsList:__len()
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    local count = rawget(self, "len")
    if not count then
        count = 0
        while offset < meta.omega do
            offset = skip(read, offset)
            count = count + 1
        end
        rawset(self, "len", count)
    end
    return count
end

function NibsList:__index(idx)
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    local count = 1
    while offset < meta.omega and count < idx do
        offset = skip(read, offset)
        count = count + 1
    end
    if count == idx then
        local value = get(read, offset, meta.scope)
        rawset(self, idx, value)
        return value
    end
end

function NibsList.__newindex()
    error "NibsList is read-only"
end

function NibsList:__ipairs()
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    local count = 0
    return function()
        if offset < meta.omega then
            count = count + 1
            local value = rawget(self, count)
            if value then
                offset = skip(read, offset)
            else
                value, offset = get(read, offset, meta.scope)
                rawset(self, count, value)
            end
            return count, value
        end
    end
end

NibsList.__pairs = NibsList.__ipairs

---@class NibsMap
NibsMap = {}
NibsMap.__name = "NibsMap"
NibsMap.__is_array_like = false

---@param read ByteProvider
---@param offset number
---@param length number
---@param scope DecodeScope?
---@return NibsMap
function NibsMap.new(read, offset, length, scope)
    local self = setmetatable({}, NibsMap)
    NibsMeta[self] = {
        read = read,
        scope = scope,
        alpha = offset,          -- Start of map values
        omega = offset + length, -- End of map values
    }
    return self
end

function NibsMap.__len()
    return 0
end

function NibsMap:__pairs()
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    return function()
        if offset < meta.omega then
            local key, value
            key, offset = get(read, offset, meta.scope)
            value = rawget(self, key)
            if value then
                offset = skip(read, offset)
            else
                value, offset = get(read, offset, meta.scope)
                rawset(self, key, value)
            end
            return key, value
        end
    end
end

function NibsMap:__index(idx)
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    while offset < meta.omega do
        local key
        key, offset = get(read, offset, meta.scope)
        if key == idx then
            local value = get(read, offset, meta.scope)
            rawset(self, idx, value)
            return value
        else
            offset = skip(read, offset)
        end
    end
end

function NibsMap.__newindex()
    error "NibsMap is read-only"
end

---@class NibsArray
NibsArray = {}
NibsArray.__name = "NibsArray"
NibsArray.__is_array_like = true
NibsArray.__is_indexed = true

---@param read ByteProvider
---@param offset number
---@param length number
---@param scope DecodeScope?
---@return NibsArray
function NibsArray.new(read, offset, length, scope)
    local self = setmetatable({}, NibsArray)
    local alpha, width, count = decode_pair(read, offset)
    local omega = offset + length
    NibsMeta[self] = {
        read = read,
        scope = scope,
        alpha = alpha, -- Start of array index
        omega = omega, -- End of array values
        width = width, -- Width of index entries
        count = count, -- Count of index entries
    }
    return self
end

function NibsArray:__index(idx)
    local meta = NibsMeta[self]
    if idx < 1 or idx > meta.count or math.floor(idx) ~= idx then return end
    local offset = meta.alpha + (idx - 1) * meta.width
    local ptr = decode_pointer(meta.read, offset, meta.width)
    offset = meta.alpha + (meta.width * meta.count) + ptr
    local value = get(meta.read, offset, meta.scope)
    return value
end

function NibsArray.__newindex()
    error "NibsArray is read-only"
end

function NibsArray:__len()
    local meta = NibsMeta[self]
    return meta.count
end

function NibsArray:__ipairs()
    local i = 0
    local count = #self
    return function()
        if i < count then
            i = i + 1
            return i, self[i]
        end
    end
end

NibsArray.__pairs = NibsArray.__ipairs

---@class NibsTrie
NibsTrie = {}
NibsTrie.__name = "NibsTrie"
NibsTrie.__is_array_like = false
NibsTrie.__is_indexed = true

---@param read ByteProvider
---@param offset number
---@param length number
---@param scope DecodeScope?
---@return NibsTrie
function NibsTrie.new(read, offset, length, scope)
    local self = setmetatable({}, NibsTrie)
    local alpha, width, count = decode_pair(read, offset)
    local seed = decode_pointer(read, alpha, width)
    local omega = offset + length
    NibsMeta[self] = {
        read = read,
        scope = scope,
        alpha = alpha, -- Start of trie index
        omega = omega, -- End of trie values
        seed = seed,   -- Seed for HAMT
        width = width, -- Width of index entries
        count = count, -- Count of index entries
    }
    return self
end

function NibsTrie:__index(idx)
    local meta = NibsMeta[self]
    local read = meta.read
    local width = assert(meta.width)
    local encoded = Nibs.encode(idx)

    local target = HamtIndex.walk(read, meta.alpha, meta.count, width, NibLib.strToBuf(encoded))
    if not target then return end

    target = tonumber(target)

    local offset = meta.alpha + meta.width * meta.count + target
    local key, value
    key, offset = get(read, offset, meta.scope)
    if key ~= idx then return end

    value = get(read, offset, meta.scope)
    return value
end

function NibsTrie.__newindex()
    error "NibsTrie is read-only"
end

function NibsTrie.__len()
    return 0
end

function NibsTrie:__pairs()
    local meta = NibsMeta[self]
    local offset = meta.alpha + meta.width * meta.count
    return function()
        if offset < meta.omega then
            local key, value
            key, offset = get(meta.read, offset, meta.scope)
            value, offset = get(meta.read, offset, meta.scope)
            -- TODO: remove this sanity check once we're confident in __index
            local check = self[key]
            if not (type(value) == "table" or type(value) == "cdata" or check == value) then
                error "Mismatch"
            end
            return key, value
        end
    end
end

---@class DecodeScope
---@field alpha number
---@field omega number

---@param read ByteProvider
---@param offset number
---@param big number
---@return any
---@return number
local function decode_scope(read, offset, big)
    return get(read, offset, {
        alpha = skip(read, offset),
        omega = offset + big,
    })
end

---@param read ByteProvider
---@param scope? DecodeScope
---@param id integer
---@return any
local function decode_ref(read, scope, id)
    assert(scope, "Ref found outside of scope")
    local offset, width, count = decode_pair(read, scope.alpha)
    assert(offset < scope.omega)
    local ptr_offset = offset + id * width
    assert(ptr_offset < scope.omega)
    local ptr = decode_pointer(read, ptr_offset, width)
    local start = offset + width * count + ptr
    assert(start < scope.omega)
    return (get(read, start, scope))
end

---Read a nibs value at offset
---@param read ByteProvider
---@param offset number
---@param scope DecodeScope?
---@return any, number
function get(read, offset, scope)
    local start = offset
    local little, big
    offset, little, big = decode_pair(read, offset)
    if little == ZIGZAG then
        return decode_zigzag(big), offset
    elseif little == FLOAT then
        return decode_float(big), offset
    elseif little == SIMPLE then
        return decode_simple(big), offset
    elseif little == REF then
        return decode_ref(read, scope, big), offset
    elseif little == BYTES then
        return decode_bytes(read, offset, big), offset + big
    elseif little == UTF8 then
        return decode_string(read, offset, big), offset + big
    elseif little == HEXSTRING then
        return decode_hexstring(read, offset, big), offset + big
    elseif little == LIST then
        return NibsList.new(read, offset, big, scope), offset + big
    elseif little == MAP then
        return NibsMap.new(read, offset, big, scope), offset + big
    elseif little == ARRAY then
        return NibsArray.new(read, offset, big, scope), offset + big
    elseif little == TRIE then
        return NibsTrie.new(read, offset, big, scope), offset + big
    elseif little == SCOPE then
        return decode_scope(read, offset, big), offset + big
    else
        error(string.format('Unexpected nibs type: %s at %08x', little, start))
    end
end

Nibs.get = get

---Decode a nibs string from memory
---@param str string
---@return any
function Nibs.decode(str)
    local val, offset = Nibs.get(function(offset, length)
        return string.sub(str, offset + 1, offset + length)
    end, 0)
    assert(offset == #str, "extra data in input string")
    return val
end

---Turn lists and maps into arrays and tries if they are over some limit
---@param value Value
---@param index_limit number
function Nibs.autoIndex(value, index_limit)
    index_limit = index_limit or 10
    -- TODO: index if the serialized size is above some threshold,
    -- this is what matters for reducing chunk fetches
    -- which matters more than overall data size

    ---@param o Value
    local function walk(o)
        if type(o) ~= "table" then return o end
        local mt = getmetatable(o)
        if mt == Ref then
            return o
        elseif mt == Scope then
            local last = #o
            o[last] = walk(o[last])
            return o
        end
        if NibLib.isArrayLike(o) then
            local r = #o < index_limit and o or Array.new()
            for i = 1, #o do
                r[i] = walk(o[i])
            end
            return r
        end
        local count = 0
        for _ in pairs(o) do count = count + 1 end
        local r = count < index_limit and o or Trie.new()
        for k, v in pairs(o) do
            r[walk(k)] = walk(v)
        end
        return r
    end

    return walk(value)
end

---Walk through a value and replace values found in the reference table with refs.
---@param value Value
---@param refs Value[]
function Nibs.addRefs(value, refs)
    if #refs == 0 then return value end
    ---@param o Value
    ---@param skipCheck boolean?
    ---@return Value
    local function walk(o, skipCheck)
        if not skipCheck then
            for i, r in ipairs(refs) do
                if r == o then
                    return Ref.new(i - 1)
                end
            end
        end
        if type(o) == "table" then
            if getmetatable(o) == Scope then return o end
            if NibLib.isArrayLike(o) then
                local a = List.new()
                for i, v in ipairs(o) do
                    a[i] = walk(v)
                end
                return a
            end
            local m = Map.new()
            for k, v in pairs(o) do
                m[walk(k)] = walk(v)
            end
            return m
        end
        return o
    end

    local scope = {}

    insert(scope, walk(value))

    for i = 1, #refs do
        insert(scope, walk(refs[i], true))
    end

    return Scope.new(scope)
end

---Walk through a value and find duplicate values (sorted by frequency)
---@param value Value
---@retun Value[]
function Nibs.findDuplicates(value)
    -- Wild guess, but real data with lots of dups over 1mb is 1 for reference
    local pointer_cost = 1
    local small_string = pointer_cost + 1
    local small_number = lshift(1, lshift(pointer_cost, 3) - 1)
    local function potentiallyBig(val)
        local t = type(val)
        if t == "string" then
            return #val > small_string
        elseif t == "number" then
            return math.floor(val) ~= val or val <= -small_number or val > small_number
        end
        return false
    end

    local seen = {}
    local duplicates = {}
    local total_encoded_size = 0
    ---@param o Value
    ---@return Value
    local function walk(o)
        if type(o) == "table" then
            -- Don't walk into nested scopes
            if getmetatable(o) == Scope then return o end
            for k, v in pairs(o) do
                walk(k)
                walk(v)
            end
        elseif o and potentiallyBig(o) then
            local old = seen[o]
            if not old then
                seen[o] = 1
            else
                if old == 1 then
                    total_encoded_size = total_encoded_size + #Nibs.encode(o)
                    table.insert(duplicates, o)
                end
                seen[o] = old + 1
            end
        end
    end

    -- Extract all duplicate values that can be potentially saved
    walk(value)

    -- Update pointer cost based on real data we now have
    -- note this is still not 100% accurate as we still need to prune any
    -- potential refs that are not worth adding and that pruning may
    -- drop this down a level.
    pointer_cost = total_encoded_size < 0x100 and 1
        or total_encoded_size < 0x10000 and 2
        or total_encoded_size < 0x100000000 and 4
        or 8

    -- Sort by frequency
    table.sort(duplicates, function(a, b)
        return seen[a] > seen[b]
    end)

    -- Remove any entries that cost more than they save
    local trimmed = {}
    local i = 0
    for _, v in ipairs(duplicates) do
        local cost = #Nibs.encode(v)
        local refCost = i < 12 and 1
            or i < 0x100 and 2
            or i < 0x10000 and 3
            or i < 0x100000000 and 5
            or 9
        local count = seen[v]
        if refCost * count + pointer_cost < cost * count then
            i = i + 1
            trimmed[i] = v
        end
    end

    -- This final list is guranteed to not contain any values that bloat the final size
    -- by turning into refs, but it had a chance to miss some it should have included.
    return trimmed
end

function Nibs.deduplicate(val)
    return Nibs.addRefs(val, Nibs.findDuplicates(val))
end

return Nibs

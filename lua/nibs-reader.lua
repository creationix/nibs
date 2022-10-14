local ordered = require 'ordered'
local Object = ordered.OrderedMap
local Array = ordered.OrderedList

local insert = table.insert
local concat = table.concat

local ffi = require 'ffi'
local cast = ffi.cast
local copy = ffi.copy

local bit = require 'bit'
local rshift = bit.rshift
local band = bit.band
local bxor = bit.bxor

local U8 = ffi.typeof 'uint8_t'
local U16 = ffi.typeof 'uint16_t'
local U32 = ffi.typeof 'uint32_t'
local U64 = ffi.typeof 'uint64_t'
local I8 = ffi.typeof 'int8_t'
local I16 = ffi.typeof 'int16_t'
local I32 = ffi.typeof 'int32_t'
local I64 = ffi.typeof 'int64_t'
local F32 = ffi.typeof 'float'
local F64 = ffi.typeof 'double'

local U8Ptr = ffi.typeof 'uint8_t*'
local U16Ptr = ffi.typeof 'uint16_t*'
local U32Ptr = ffi.typeof 'uint32_t*'
local U64Ptr = ffi.typeof 'uint64_t*'

local Slice8 = ffi.typeof 'uint8_t[?]'
local Slice16 = ffi.typeof 'uint16_t[?]'
local Slice32 = ffi.typeof 'uint32_t[?]'
local Slice64 = ffi.typeof 'uint64_t[?]'

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

---@class NibsReader
local NibsReader = {}

---@param read ByteProvider
---@param offset number
---@return number
---@return number
---@return number
local function decode_pair(read, offset)
    local data = read(offset, 9)
    local ptr = cast(U8Ptr, data)
    local head = ptr[0]
    local little = rshift(head, 4)
    local big = band(head, 0xf)
    if big == 0xc then
        return offset + 2, little, ptr[1]
    elseif big == 0xd then
        return offset + 3, little, cast(U16Ptr, ptr + 1)[0]
    elseif big == 0xe then
        return offset + 5, little, cast(U32Ptr, ptr + 1)[0]
    elseif big == 0xf then
        return offset + 9, little, cast(U64Ptr, ptr + 1)[0]
    else
        return offset + 1, little, big
    end
end

local function tonumberMaybe(n)
    local nn = tonumber(n)
    return nn == n and nn or n
end

---Convert a nibs big from zigzag to I64
---@param big integer
---@return integer
local function decode_zigzag(big)
    local i = I64(big)
    return tonumberMaybe(bxor(rshift(i, 1), -band(i, 1)))
end

local converter = ffi.new 'union {double f;uint64_t i;}'

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
    local data = read(offset, length)
    local ptr = cast(U8Ptr, data)
    local bytes = Slice8(length)
    copy(bytes, ptr, length)
    return bytes
end

---@param read ByteProvider
---@param offset number
---@param length number
---@return string
local function decode_string(read, offset, length)
    return read(offset, length)
end

-- Convert integer to ascii code for hex digit
local function tohex(num)
    return num + (num < 10 and 48 or 87)
end

---@param read ByteProvider
---@param offset number
---@param length number
---@return string
local function decode_hexstring(read, offset, length)
    local bytes = read(offset, length)
    local chars = Slice8(length * 2)
    for i = 1, length do
        local b = string.byte(bytes, i, i)
        chars[i * 2 - 2] = tohex(rshift(b, 4))
        chars[i * 2 - 1] = tohex(band(b, 15))
    end
    return ffi.string(chars, length * 2)
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
---@field alpha number start of data as offset
---@field omega number end of data as offset to after data
---@field width number? width of index entries
---@field count number? count of index entries

-- Weakmap for associating private metadata to tables.
---@type table<table,NibsMetaEntry>
local NibsMeta = setmetatable({}, { __mode = "k" })

---@class NibsList
local NibsList = {}

NibsList.__name = "NibsList"

---@param read ByteProvider
---@param offset number
---@param length number
---@return NibsList
function NibsList.new(read, offset, length)
    local self = setmetatable({}, NibsList)
    NibsMeta[self] = {
        read = read,
        alpha = offset, -- Start of list values
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
        local value = get(read, offset)
        rawset(self, idx, value)
        return value
    end
end

function NibsList:__ipairs()
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    local count = 0
    return coroutine.wrap(function()
        while offset < meta.omega do
            count = count + 1
            local value = rawget(self, count)
            if value then
                offset = skip(read, offset)
            else
                value, offset = get(read, offset)
                rawset(self, count, value)
            end
            coroutine.yield(count, value)
        end
    end)
end

NibsList.__pairs = NibsList.__ipairs

function NibsList:__tostring()
    local parts = { "[" }
    for i, v in ipairs(self) do
        if i > 1 then
            insert(parts, ",")
        end
        insert(parts, tostring(v))
    end
    insert(parts, "]")
    return concat(parts)
end

---@class NibsMap
local NibsMap = {}

NibsMap.__name = "NibsMap"

---@param read ByteProvider
---@param offset number
---@param length number
---@return NibsMap
function NibsMap.new(read, offset, length)
    local self = setmetatable({}, NibsMap)
    NibsMeta[self] = {
        read = read,
        alpha = offset, -- Start of map values
        omega = offset + length, -- End of map values
    }
    return self
end

function NibsMap:__len()
    return 0
end

function NibsMap:__pairs()
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    return coroutine.wrap(function()
        while offset < meta.omega do
            local key, value
            key, offset = get(read, offset)
            value = rawget(self, key)
            if value then
                offset = skip(read, offset)
            else
                value, offset = get(read, offset)
                rawset(self, key, value)
            end
            coroutine.yield(key, value)
        end
    end)
end

function NibsMap:__index(idx)
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    while offset < meta.omega do
        local key
        key, offset = get(read, offset)
        if key == idx then
            local value = get(read, offset)
            rawset(self, idx, value)
            return value
        else
            offset = skip(read, offset)
        end
    end
end

function NibsMap:__tostring()
    local parts = { "{" }
    local first = true
    for k, v in pairs(self) do
        if not first then
            insert(parts, ",")
        end
        first = false
        insert(parts, tostring(k) .. ":" .. tostring(v))
    end
    insert(parts, "}")
    return concat(parts)
end

---@class NibsArray
local NibsArray = {}

NibsArray.__name = "NibsArray"

---@param read ByteProvider
---@param offset number
---@param length number
---@return NibsArray
function NibsArray.new(read, offset, length)
    local self = setmetatable({}, NibsArray)
    local alpha, width, count = decode_pair(read, offset)
    local omega = offset + length
    NibsMeta[self] = {
        read = read,
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
    local value = get(meta.read, offset)
    return value
end

function NibsArray:__len()
    local meta = NibsMeta[self]
    return meta.count
end

function NibsArray:__ipairs()
    return coroutine.wrap(function()
        for i = 1, #self do
            coroutine.yield(i, self[i])
        end
    end)
end

NibsArray.__pairs = NibsArray.__ipairs

NibsArray.__tostring = NibsList.__tostring

---@class NibsTrie
local NibsTrie = {}

NibsTrie.__name = "NibsTrie"

---@param read ByteProvider
---@param offset number
---@param length number
---@return NibsTrie
function NibsTrie.new(read, offset, length)
    local self = setmetatable({}, NibsTrie)
    NibsMeta[self] = {
        read = read,
        offset = offset,
        len = length,
    }
    return self
end

function NibsTrie:__index(idx)
    error "TODO: NibsTrie:__index"
end

function NibsTrie:__len()
    error "TODO: NibsTrie:__len"
end

function NibsTrie:__pairs()
    error "TODO: NibsTrie:__pairs"
end

---Read a nibs value at offset
---@param read ByteProvider
---@param offset number
---@return any, number
function get(read, offset)
    local little, big
    offset, little, big = decode_pair(read, offset)
    if little == ZIGZAG then
        return decode_zigzag(big), offset
    elseif little == FLOAT then
        return decode_float(big), offset
    elseif little == SIMPLE then
        return decode_simple(big), offset
    elseif little == REF then
        error "TODO: decode ref"
    elseif little == BYTES then
        return decode_bytes(read, offset, big), offset + big
    elseif little == UTF8 then
        return decode_string(read, offset, big), offset + big
    elseif little == HEXSTRING then
        return decode_hexstring(read, offset, big), offset + big
    elseif little == LIST then
        return NibsList.new(read, offset, big), offset + big
    elseif little == MAP then
        return NibsMap.new(read, offset, big), offset + big
    elseif little == ARRAY then
        return NibsArray.new(read, offset, big), offset + big
    elseif little == TRIE then
        return NibsTrie.new(read, offset, big), offset + big
    elseif little == SCOPE then
        error "TODO: decode scope"
    else
        error('Unexpected nibs type: ' .. little)
    end
end

NibsReader.get = get

return NibsReader

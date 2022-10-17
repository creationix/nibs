local Nibs = require "nibs2"
local xxh64 = require 'xxhash64'
local nibs = Nibs:new()

local insert = table.insert
local concat = table.concat

local ffi = require 'ffi'
local cast = ffi.cast
local copy = ffi.copy

local bit = require 'bit'
local rshift = bit.rshift
local lshift = bit.lshift
local band = bit.band
local bxor = bit.bxor

local I64 = ffi.typeof 'int64_t'

local U8Ptr = ffi.typeof 'uint8_t*'
local U16Ptr = ffi.typeof 'uint16_t*'
local U32Ptr = ffi.typeof 'uint32_t*'
local U64Ptr = ffi.typeof 'uint64_t*'

local Slice8 = ffi.typeof 'uint8_t[?]'

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
    local data = read(tonumber(offset), 9)
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

local UintPtrs = {
    [3] = U8Ptr,
    [4] = U16Ptr,
    [5] = U32Ptr,
    [6] = U64Ptr,
}
-- http://graphics.stanford.edu/~seander/bithacks.html#CountBitsSetNaive
local function popcnt(v)
    local c = 0
    while v > 0 do
        c = c + band(v, 1ULL)
        v = rshift(v, 1ULL)
    end
    return c
end

--- Walk a HAMT index checking for matching offset output
---@param read ByteProvider
---@param offset number
---@param hash integer u64 hash of key
---@param bits number bits per path segment (3 for 8 bit, 4 for 16 bit, etc...)
---@return integer? result usually an offset
local function hamtWalk(read, offset, hash, bits)
    local UintPtr = assert(UintPtrs[bits], "Invalid segment bit width")
    local width = lshift(1, bits - 3)
    local segmentMask = lshift(1, bits) - 1
    local highBit = lshift(1ULL, segmentMask)

    while true do

        -- Consume the next path segment
        local segment = band(hash, segmentMask)
        hash = rshift(hash, bits)

        -- Read the next bitfield
        local bitfield = cast(UintPtr, read(offset, width))[0]
        offset = offset + width

        -- Check if segment is in bitfield
        local match = lshift(1, segment)
        if band(bitfield, match) == 0 then return end

        -- If it is, calculate how many pointers to skip by counting 1s under it.
        local skipCount = tonumber(popcnt(band(bitfield, match - 1)))

        -- Jump to the pointer and read it
        offset = offset + skipCount * width
        local ptr = cast(U8Ptr, read(offset, width))[0]

        -- If there is a leading 1, it's a result pointer.
        if band(ptr, highBit) > 0 then
            return band(ptr, highBit - 1)
        end

        -- Otherwise it's an internal pointer
        offset = offset + 1 + ptr
    end
end

local get

---@class NibsMetaEntry
---@field read ByteProvider
---@field scope Scope? optional ref scope chain
---@field alpha number start of data as offset
---@field omega number end of data as offset to after data
---@field width number? width of index entries
---@field count number? count of index entries
---@field seed number? hash seed for trie hamt

-- Weakmap for associating private metadata to tables.
---@type table<table,NibsMetaEntry>
local NibsMeta = setmetatable({}, { __mode = "k" })

---@class NibsList
local NibsList = {}

NibsList.__name = "NibsList"

---@param read ByteProvider
---@param offset number
---@param length number
---@param scope Scope?
---@return NibsList
function NibsList.new(read, offset, length, scope)
    local self = setmetatable({}, NibsList)
    NibsMeta[self] = {
        read = read,
        scope = scope,
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
        local value = get(read, offset, meta.scope)
        rawset(self, idx, value)
        return value
    end
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
---@param scope Scope?
---@return NibsMap
function NibsMap.new(read, offset, length, scope)
    local self = setmetatable({}, NibsMap)
    NibsMeta[self] = {
        read = read,
        scope = scope,
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
---@param scope Scope?
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

NibsArray.__tostring = NibsList.__tostring

---@class NibsTrie
local NibsTrie = {}

NibsTrie.__name = "NibsTrie"

---@param read ByteProvider
---@param offset number
---@param length number
---@param scope Scope?
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
        seed = seed, -- Seed for HAMT
        width = width, -- Width of index entries
        count = count, -- Count of index entries
    }
    return self
end

function NibsTrie:__index(idx)
    local meta = NibsMeta[self]
    local read = meta.read
    local offset = meta.alpha + meta.width
    local encoded = nibs:encode(idx)
    local hash = xxh64(cast(U8Ptr, encoded), #encoded, meta.seed)

    local bits = assert(meta.width == 1 and 3
        or meta.width == 2 and 4
        or meta.width == 4 and 5
        or meta.width == 8 and 6
        or nil, "Invalid byte width")

    local target = hamtWalk(read, offset, hash, bits)
    if not target then return end

    target = tonumber(target)

    offset = meta.alpha + meta.width * meta.count + target
    local key, value
    key, offset = get(read, offset, meta.scope)
    if key ~= idx then return end

    value = get(read, offset, meta.scope)
    return value
end

function NibsTrie:__len()
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
            return key, value
        end
    end
end

NibsTrie.__tostring = NibsMap.__tostring

---@class EncodeScope
---@field parent EncodeScope?
---@field alpha number
---@field omega number
---@field width number
---@field count number

local function decode_scope(read, offset, big, scope)
    local alpha, width, count = decode_pair(read, offset)
    return get(read, alpha + width * count, {
        parent = scope,
        alpha = alpha,
        omega = offset + big,
        width = width,
        count = count
    })
end

local function decode_ref(read, scope, big)
    assert(scope, "Ref found outside of scope")
    local ptr = decode_pointer(read, scope.alpha + big * scope.width, scope.width)
    local start = scope.alpha + scope.width * scope.count + ptr
    return get(read, start)
end

---Read a nibs value at offset
---@param read ByteProvider
---@param offset number
---@param scope Scope?
---@return any, number
function get(read, offset, scope)
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
        return decode_scope(read, offset, big, scope), offset + big
    else
        error('Unexpected nibs type: ' .. little)
    end
end

NibsReader.get = get

return NibsReader
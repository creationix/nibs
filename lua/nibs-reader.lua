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

---@param provider ByteProvider
---@param offset number
---@return number
---@return number
---@return number
local function decode_pair(provider, offset)
    local data = provider(offset, 9)
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

---@param provider ByteProvider
---@param offset number
---@param length number
---@return ffi.ctype*
local function decode_bytes(provider, offset, length)
    local data = provider(offset, length)
    local ptr = cast(U8Ptr, data)
    local bytes = Slice8(length)
    copy(bytes, ptr, length)
    return bytes
end

---@param provider ByteProvider
---@param offset number
---@param length number
---@return string
local function decode_string(provider, offset, length)
    return provider(offset, length)
end

-- Convert integer to ascii code for hex digit
local function tohex(num)
    return num + (num < 10 and 48 or 87)
end

---@param provider ByteProvider
---@param offset number
---@param length number
---@return string
local function decode_hexstring(provider, offset, length)
    local bytes = provider(offset, length)
    local chars = Slice8(length * 2)
    for i = 1, length do
        local b = string.byte(bytes, i, i)
        chars[i * 2 - 2] = tohex(rshift(b, 4))
        chars[i * 2 - 1] = tohex(band(b, 15))
    end
    return ffi.string(chars, length * 2)
end

local function skip(provider, offset)
    local little, big
    offset, little, big = decode_pair(provider, offset)
    if little < 8 then
        return offset
    else
        return offset + big
    end
end

-- Weakmap for associating private metadata to tables.
local NibsMeta = setmetatable({}, { __mode = "k" })

---@class NibsList
local NibsList = {}

function NibsList.new(provider, offset, length)
    local self = setmetatable({}, NibsList)
    NibsMeta[self] = {
        provider = provider,
        offset = offset,
        len = length,
    }
    return self
end

function NibsList:__len()
    local meta = NibsMeta[self]
    local offset = meta.offset
    local last = offset + meta.len
    local provider = meta.provider
    local count = 0
    while offset < last do
        offset = skip(provider, offset)
        count = count + 1
    end
    return count
end

function NibsList:__index(key)
    local meta = NibsMeta[self]
    local offset = meta.offset
    local last = offset + meta.len
    local provider = meta.provider
    local count = 1
    while offset < last and count < key do
        offset = skip(provider, offset)
        count = count + 1
    end
    if count == key then
        local value = NibsReader.get(provider, offset)
        return value
    end
end

function NibsList:__ipairs()
    local meta = NibsMeta[self]
    local offset = meta.offset
    local last = offset + meta.len
    local provider = meta.provider
    local count = 0
    return coroutine.wrap(function()
        while offset < last do
            local value
            value, offset = NibsReader.get(provider, offset)
            count = count + 1
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

function NibsMap.new(provider, offset, length)
    local self = setmetatable({}, NibsMap)
    NibsMeta[self] = {
        provider = provider,
        offset = offset,
        len = length,
    }
    return self
end

function NibsMap:__pairs()
    local meta = NibsMeta[self]
    local offset = meta.offset
    local last = offset + meta.len
    local provider = meta.provider
    return coroutine.wrap(function()
        while offset < last do
            local key, value
            key, offset = NibsReader.get(provider, offset)
            value, offset = NibsReader.get(provider, offset)
            coroutine.yield(key, value)
        end
    end)
end

function NibsMap:__index(idx)
    local meta = NibsMeta[self]
    local offset = meta.offset
    local last = offset + meta.len
    local provider = meta.provider
    while offset < last do
        local key
        key, offset = NibsReader.get(provider, offset)
        if key == idx then
            return NibsReader.get(provider, offset)
        else
            offset = skip(provider, offset)
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

---Read a nibs value at offset
---@param provider ByteProvider
---@param offset number
---@return any, number
local function get(provider, offset)
    local little, big
    offset, little, big = decode_pair(provider, offset)
    if little == ZIGZAG then
        return decode_zigzag(big), offset
    elseif little == FLOAT then
        return decode_float(big), offset
    elseif little == SIMPLE then
        return decode_simple(big), offset
    elseif little == REF then
        error "TODO: decode ref"
    elseif little == BYTES then
        return decode_bytes(provider, offset, big), offset + big
    elseif little == UTF8 then
        return decode_string(provider, offset, big), offset + big
    elseif little == HEXSTRING then
        return decode_hexstring(provider, offset, big), offset + big
    elseif little == LIST then
        return NibsList.new(provider, offset, big), offset + big
    elseif little == MAP then
        return NibsMap.new(provider, offset, big), offset + big
    elseif little == ARRAY then
        error "TODO: decode array"
    elseif little == TRIE then
        error "TODO: decode trie"
    elseif little == SCOPE then
        error "TODO: decode scope"
    else
        error('Unexpected nibs type: ' .. little)
    end
end

NibsReader.get = get

return NibsReader

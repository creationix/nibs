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
        return 2, little, ptr[1]
    elseif big == 0xd then
        return 3, little, cast(U16Ptr, ptr + 1)[0]
    elseif big == 0xe then
        return 5, little, cast(U32Ptr, ptr + 1)[0]
    elseif big == 0xf then
        return 9, little, cast(U64Ptr, ptr + 1)[0]
    else
        return 1, little, big
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
---@param len number
---@return ffi.ctype*
---@return number
local function decode_bytes(provider, offset, len)
    local data = provider(offset, len)
    local ptr = cast(U8Ptr, data)
    local bytes = Slice8(len)
    copy(bytes, ptr + offset, len)
    return bytes, offset + len
end

---@param provider ByteProvider
---@param offset number
---@param len number
---@return string
---@return number
local function decode_string(provider, offset, len)
    return provider(offset, len), offset + len
end

-- Convert integer to ascii code for hex digit
local function tohex(num)
    return num + (num < 10 and 48 or 87)
end

---@param provider ByteProvider
---@param offset number
---@param len number
---@return string
---@return number
local function decode_hexstring(provider, offset, len)
    local bytes = provider(offset, len)
    local chars = Slice8(len * 2)
    for i = 1, len do
        local b = string.byte(bytes, i, i)
        chars[i * 2 - 2] = tohex(rshift(b, 4))
        chars[i * 2 - 1] = tohex(band(b, 15))
    end
    return ffi.string(chars, len * 2), offset + len
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
        return decode_bytes(provider, offset, big)
    elseif little == UTF8 then
        return decode_string(provider, offset, big)
    elseif little == HEXSTRING then
        return decode_hexstring(provider, offset, big)
    elseif little == LIST then
        error "TODO: decode list"
    elseif little == MAP then
        error "TODO: decode map"
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

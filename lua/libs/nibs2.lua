-- Main types
local INT = 0
local FLOAT = 1
local SIMPLE = 2
local REF = 3
local TAG = 7
local BYTE = 8
local STRING = 9
local TUPLE = 10
local MAP = 11
local ARRAY = 12
-- Simple subtypes
local FALSE = 0
local TRUE = 1
local NULL = 2

local bit = require 'bit'
local rshift = bit.rshift
local band = bit.band
local lshift = bit.lshift
local bor = bit.bor
local bxor = bit.bxor

local ffi = require 'ffi'
local sizeof = ffi.sizeof
local copy = ffi.copy
local ffi_string = ffi.string
local cast = ffi.cast
local istype = ffi.istype
local metatype = ffi.metatype

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

local Slice8 = ffi.typeof 'uint8_t[?]'
local Slice16 = ffi.typeof 'uint16_t[?]'
local Slice32 = ffi.typeof 'uint32_t[?]'
local Slice64 = ffi.typeof 'uint64_t[?]'

local tohex = bit.tohex
local byte = string.byte
local concat = table.concat

local function dump_string(str)
    local parts = {}
    for i = 1, #str do
        parts[i] = tohex(byte(str, i), 2)
    end
    return '"' .. concat(parts) .. '"'
end

---Encode a small/big pair into binary parts
---@param small integer any 4-bit unsigned integer
---@param big integer and 64-bit unsigned integer
---@return integer size of encoded bytes
---@return any bytes as parts
local function encode_pair(small, big)
    local pair = lshift(small, 4)
    if big < 0xc then
        return 1, tonumber(bor(pair, big))
    elseif big < 0x100 then
        return 2, Slice8(2, { bor(pair, 12), big })
    elseif big < 0x10000 then
        return 3, { bor(pair, 13), Slice16(1, { big }) }
    elseif big < 0x100000000ULL then
        return 5, { bor(pair, 14), Slice32(1, { big }) }
    else
        return 9, { bor(pair, 15), Slice64(1, { big }) }
    end
end

---@param num integer
---@return integer
local function encode_zigzag(num)
    return num < 0 and num * -2 - 1 or num * 2
end

local converter = ffi.new 'union {double f;uint64_t i;}'
---@param val number
---@return integer
local function encode_float(val)
    converter.f = val
    return converter.i
end

---Combine binary parts into a single binary string
---@param size integer total number of expected bytes
---@param parts any parts to combine
---@return string
local function combine(size, parts)
    p(size, parts)
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
            local len = sizeof(part)
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
    return ffi_string(buf, size)
end

---@class TagType
---@field encode fun()
---@field decode fun()

---@class Nibs
---@field refs table<integer,any> map from ref ID to value
---@field refsIdx table<any,integer> map from ref value to ID
---@field tags table<integer,TagType> map from tag ID to TagType
local Nibs = {}
local NibsMeta = { __index = Nibs }

function Nibs.new()
    return setmetatable({
        refs = {},
        refsIdx = {},
        tags = {},
    }, NibsMeta)
end

---Encode any value into a nibs encoded binary string
---@param val any
---@return string
function Nibs:encode(val)
    local encoded = combine(self:encode_any(val))
    p(val, encoded)
    print(dump_string(encoded))
    return encoded
end

---@private
---@param val any
---@return integer size of encoded bytes
---@return any bytes as parts
function Nibs:encode_any(val)
    local t = type(val)
    if t == "number" then
        if val % 1 == 0 then
            return encode_pair(INT, encode_zigzag(val))
        else
            return encode_pair(FLOAT, encode_float(val))
        end
    elseif t == "string" then
        local len = #val
        local size, head = encode_pair(STRING, len)
        return size + len, { head, val }
    elseif t == "cdata" then
        if istype(I64, val) or istype(I32, val) or istype(I16, val) or istype(I8, val) or
            istype(U64, val) or istype(U32, val) or istype(U16, val) or istype(U8, val) then
            -- Treat cdata integers as integers
            return encode_pair(INT, encode_zigzag(val))
        elseif istype(F64, val) or istype(F32, val) then
            -- Treat cdata floats as floats
            return encode_pair(FLOAT, encode_float(val))
        else
            local len = sizeof(val)
            local size, head = encode_pair(BYTE, len)
            return size + len, { head, val }
        end
    elseif t == "boolean" then
        return encode_pair(SIMPLE, val and TRUE or FALSE)
    elseif t == "nil" then
        return encode_pair(SIMPLE, NULL)
    else
        error(string.format("Unsupported type %s", t))
    end

end

return Nibs

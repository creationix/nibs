local bit = require 'bit'
local rshift = bit.rshift
local lshift = bit.lshift
local band = bit.band
local bor = bit.bor

local byte = string.byte

local ffi = require 'ffi'
local cast = ffi.cast
local sizeof = ffi.sizeof
local ffi_string = ffi.string
local istype = ffi.istype
local copy = ffi.copy

local NibLib = {
    U8Arr = ffi.typeof 'uint8_t[?]',
    U16Arr = ffi.typeof 'uint16_t[?]',
    U32Arr = ffi.typeof 'uint32_t[?]',
    U64Arr = ffi.typeof 'uint64_t[?]',
    U8Ptr = ffi.typeof 'uint8_t*',
    U16Ptr = ffi.typeof 'uint16_t*',
    U32Ptr = ffi.typeof 'uint32_t*',
    U64Ptr = ffi.typeof 'uint64_t*',
    U8 = ffi.typeof 'uint8_t',
    U16 = ffi.typeof 'uint16_t',
    U32 = ffi.typeof 'uint32_t',
    U64 = ffi.typeof 'uint64_t',
    I8 = ffi.typeof 'int8_t',
    I16 = ffi.typeof 'int16_t',
    I32 = ffi.typeof 'int32_t',
    I64 = ffi.typeof 'int64_t',
    F32 = ffi.typeof 'float',
    F64 = ffi.typeof 'double',
}

local U8Arr = NibLib.U8Arr
local U8Ptr = NibLib.U8Ptr
local U16Ptr = NibLib.U16Ptr
local U32Ptr = NibLib.U32Ptr
local U64Ptr = NibLib.U64Ptr
local U8 = NibLib.U8
local U16 = NibLib.U16
local U32 = NibLib.U32
local U64 = NibLib.U64
local I8 = NibLib.I8
local I16 = NibLib.I16
local I32 = NibLib.I32
local I64 = NibLib.I64
local F32 = NibLib.F32
local F64 = NibLib.F64

function NibLib.decodePointer(read, offset, width)
    local str = read(offset, width)
    if width == 1 then return cast(U8Ptr, str)[0] end
    if width == 2 then return cast(U16Ptr, str)[0] end
    if width == 4 then return cast(U32Ptr, str)[0] end
    if width == 8 then return cast(U64Ptr, str)[0] end
    error("Illegal pointer width " .. width)
end

--- Returns true if a table should be treated like an array (ipairs/length/etc)
--- This uses the __is_array_like metaproperty if it exists, otherwise, it
--- iterates over the pairs keys checking if they look like an array (1...n)
---@param val table
---@return boolean is_array_like
function NibLib.isArrayLike(val)
    local mt = getmetatable(val)
    if mt and mt.__is_array_like ~= nil then
        return mt.__is_array_like
    end
    local i = 1
    for key in pairs(val) do
        if key ~= i then return false end
        i = i + 1
    end
    return true
end

--- Detect if a cdata is an integer
---@param val ffi.cdata*
---@return boolean is_int
function NibLib.isInteger(val)
    return istype(I64, val) or
        istype(I32, val) or
        istype(I16, val) or
        istype(I8, val) or
        istype(U64, val) or
        istype(U32, val) or
        istype(U16, val) or
        istype(U8, val)
end

--- Detect if a cdata is a float
---@param val ffi.cdata*
---@return boolean is_float
function NibLib.isFloat(val)
    return istype(F64, val) or
        istype(F32, val)
end

--- Detect if a number is whole or not
---@param num number|ffi.cdata*
function NibLib.isWhole(num)
    local t = type(num)
    if t == 'cdata' then
        return NibLib.isInteger(num)
    elseif t == 'number' then
        return not (num ~= num or num == 1 / 0 or num == -1 / 0 or math.floor(num) ~= num)
    end
end

--- Convert integer to ascii code for hex digit
--- Assumes input is valid number (0-15)
---@param num integer numerical value (0-15)
---@return integer code ascii hex digit [0-9a-f]
local function tohex(num)
    return num + (num <= 9 and 0x30 or 0x57)
end

--- Convert ascii hex digit to integer
--- Assumes input is valid character [0-9a-f]
---@param code integer ascii code for hex digit
---@return integer num value of hex digit (0-15)
local function fromhex(code)
    return code - (code >= 0x61 and 0x57 or 0x30)
end

---Turn any buffer into a hex encoded binary buffer
---@param str string
---@return ffi.cdata* hex
function NibLib.strToHexBuf(str)
    local len = #str
    local buf = U8Arr(len * 2)
    for i = 1, len do
        local b = byte(str, i)
        buf[i * 2 - 2] = tohex(rshift(b, 4))
        buf[i * 2 - 1] = tohex(band(b, 15))
    end
    return buf
end

---Turn any lua string into a hex encoded binary buffer
---@param str string
---@return string hex
function NibLib.strToHexStr(str)
    local buf = NibLib.strToHexBuf(str)
    local hex = ffi_string(buf, sizeof(buf))
    return hex
end

---Turn any buffer into a hex encoded binary buffer
---@param dat ffi.cdata*
---@return ffi.cdata* hex
function NibLib.bufToHexBuf(dat)
    local len = sizeof(dat)
    local ptr = cast(U8Ptr, dat) -- input can be any cdata, not just slice8
    local buf = U8Arr(len * 2)
    for i = 0, len - 1 do
        local b = ptr[i]
        buf[i * 2] = tohex(rshift(b, 4))
        buf[i * 2 + 1] = tohex(band(b, 15))
    end
    return buf
end

---Turn any buffer into a hex encoded binary string
---@param dat ffi.cdata*
---@return string hex
function NibLib.bufToHexStr(dat)
    local buf = NibLib.bufToHexBuf(dat)
    local hex = ffi_string(buf, sizeof(buf))
    return hex
end

--- Decode a hex encoded string into a binary buffer
---@param hex string
---@return ffi.cdata* buf
function NibLib.hexStrToBuf(hex)
    local len = #hex / 2
    local buf = U8Arr(len)
    for i = 0, len - 1 do
        buf[i] = bor(
            lshift(fromhex(byte(hex, i * 2 + 1)), 4),
            fromhex(byte(hex, i * 2 + 2))
        )
    end
    return buf
end

--- Decode a hex encoded string into a raw string
---@param hex string
---@return string str
function NibLib.hexStrToStr(hex)
    local buf = NibLib.hexStrToBuf(hex)
    return ffi_string(buf, sizeof(buf))
end

--- Decode a hex encoded buffer into a binary buffer
---@param hex ffi.cdata*
---@return ffi.cdata* buf
function NibLib.hexBufToBuf(hex)
    local len = sizeof(hex) / 2
    local ptr = cast(U8Ptr, hex) -- input can be any cdata, not just slice8
    local buf = U8Arr(len)
    for i = 0, len - 1 do
        buf[i] = bor(
            lshift(fromhex(ptr[i * 2]), 4),
            fromhex(ptr[i * 2 + 1])
        )
    end
    return buf
end

--- Decode a hex encoded buffer into a raw string
---@param hex ffi.cdata*
---@return string str
function NibLib.hexBufToStr(hex)
    local buf = NibLib.hexBufToBuf(hex)
    return ffi_string(buf, sizeof(buf))
end

function NibLib.strToBuf(str)
    local len = #str
    local buf = U8Arr(len)
    copy(buf, str, len)
    return buf
end

function NibLib.bufToStr(buf)
    return ffi_string(buf, sizeof(buf))
end

--- Convert an I64 to a normal number if it's in the safe range
---@param n integer cdata I64
---@return integer|number maybeNum
function NibLib.tonumberMaybe(n)
    return (n <= 0x1fffffffffffff and n >= -0x1fffffffffffff)
        and tonumber(n)
        or n
end

return NibLib

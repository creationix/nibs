local bit = require 'bit'
local rshift = bit.rshift
local band = bit.band
local bxor = bit.bxor

local ffi = require 'ffi'
local cast = ffi.cast
local copy = ffi.copy
local U8Arr = ffi.typeof 'uint8_t[?]'
local U8Ptr = ffi.typeof 'uint8_t*'
local U16Ptr = ffi.typeof 'uint16_t*'
local U32Ptr = ffi.typeof 'uint32_t*'
local U64Ptr = ffi.typeof 'uint64_t*'
local I64 = ffi.typeof 'int64_t'
local converter = ffi.new 'union {double f;uint64_t i;}'

local Nibs = {}

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

local function read_pair(ptr)
  local high = rshift(ptr[0], 4)
  local low = band(ptr[0], 15)
  if low < 12 then
    return ptr + 1, high, low
  elseif low == 12 then
    return ptr + 2, high, cast(U8Ptr, ptr + 1)[0]
  elseif low == 13 then
    return ptr + 3, high, cast(U16Ptr, ptr + 1)[0]
  elseif low == 14 then
    return ptr + 5, high, cast(U32Ptr, ptr + 1)[0]
  else
    return ptr + 9, high, cast(U64Ptr, ptr + 1)[0]
  end
end

---Convert an unsigned 64 bit integer to a signed 64 bit integer using zigzag decoding
---@param num integer
---@return integer
local function decode_zigzag(num)
  local i = I64(num)
  local o = bxor(rshift(i, 1), -band(i, 1))
  if num <= 0x1fffffffffffff and num >= -0x1fffffffffffff then
    return tonumber(num)
  end
  return num
end

--- Convert an unsigned 64 bit integer to a double precision floating point by casting the bits
---@param val number
---@return integer
local function decode_float(val)
  converter.i = val
  return converter.f
end


local function decode_any(ptr)
  local high, low
  ptr, high, low = read_pair(ptr)
  if high == ZIGZAG then
    return decode_zigzag(low)
  elseif high == FLOAT then
    return decode_float(low)
  elseif high == BYTES then
    local buf = U8Arr(low)
    copy(buf, ptr, low)
    return buf
  end
  print(ptr, high, low)
  error("TODO: handle type " .. high)
end

function Nibs.decode_string(str)
  return decode_any(cast(U8Ptr, str))
end

return Nibs

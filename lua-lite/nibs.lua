local bit = require 'bit'
local rshift = bit.rshift
local band = bit.band

local ffi = require 'ffi'
local cast = ffi.cast
local U8Ptr = ffi.typeof 'uint8_t*'
local U16Ptr = ffi.typeof 'uint16_t*'
local U32Ptr = ffi.typeof 'uint32_t*'
local U64Ptr = ffi.typeof 'uint64_t*'


local Nibs = {}

local function read_pair(ptr)
  local high = rshift(ptr[0], 4)
  local low = band(ptr[0], 7)
  if low < 12 then
    return ptr + 1, high, low
  elseif low == 12 then
    return ptr + 2, high, ptr[1]
  elseif low == 13 then
    return ptr + 3, high, cast(U16Ptr, ptr + 1)[0]
  elseif low == 14 then
    return ptr + 5, high, cast(U32Ptr, ptr + 1)[0]
  else
    return ptr + 9, high, cast(U64Ptr, ptr + 1)[0]
  end
end

Nibs.read_pair = read_pair

return Nibs

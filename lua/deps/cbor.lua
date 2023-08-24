--[[lit-meta
  name = "creationix/cbor"
  version = "1.1.0"
  homepage = "https://github.com/creationix/luajit-cbor"
  description = "Pure luajit implementation of a subset of cbor."
  tags = {"hash", "cbor", "ffi", "luajit"}
  license = "MIT"
  author = { name = "Tim Caswell" }
]]

local ffi = require 'ffi'
local typeof = ffi.typeof
local istype = ffi.istype
local sizeof = ffi.sizeof
local bit = require 'bit'
local bor = bit.bor
local rshift = bit.rshift
local lshift = bit.lshift
local band = bit.band
local char = string.char
local byte = string.byte
local sub = string.sub
local concat = table.concat

local u64 = typeof 'uint64_t'
local buf = typeof 'uint8_t[?]'

local function bin(str)
  return buf(#str, str)
end

local tags = {}
local function registerTag(num, tagDecoder)
  tags[num] = tagDecoder
end

local encoders = {}
local function encode(obj)
  return encoders[type(obj)](obj)
end

local function encode_integer(major, num)
  assert(num >= 0)
  if num >= 0x100000000 and type(num) == 'number' then
    num = u64(num)
  end
  if istype(u64, num) then
    return concat {
      char(bor(major, 27)),
      char(tonumber(rshift(num, 56))),
      char(tonumber(band(rshift(num, 48), 0xff))),
      char(tonumber(band(rshift(num, 40), 0xff))),
      char(tonumber(band(rshift(num, 32), 0xff))),
      char(tonumber(band(rshift(num, 24), 0xff))),
      char(tonumber(band(rshift(num, 16), 0xff))),
      char(tonumber(band(rshift(num, 8), 0xff))),
      char(tonumber(band(num, 0xff)))
    }
  elseif num < 24 then
    return char(bor(major, num))
  elseif num < 0x100 then
    return char(bor(major, 24)) .. char(num)
  elseif num < 0x10000 then
    return concat {
      char(bor(major, 25)),
      char(rshift(num, 8)),
      char(band(num, 0xff))
    }
  else
    return concat {
      char(bor(major, 26)),
      char(rshift(num, 24)),
      char(band(rshift(num, 16), 0xff)),
      char(band(rshift(num, 8), 0xff)),
      char(band(num, 0xff))
    }
  end
end

encoders['nil'] = function ()
  return '\xf6'
end

encoders.boolean = function (bool)
  return bool and '\xf5' or '\xf4'
end

encoders.number = function (num)
  -- TODO: handle floats
  if num >= 0 then
    return encode_integer(0x00, num)
  else
    return encode_integer(0x20, -1 - num)
  end
end

encoders.string = function (str)
  return encode_integer(0x60, #str) .. str
end

encoders.cdata = function (val)
  if istype(u64, val) then
    return encode_integer(0x00, val)
  end
  if istype(buf, val) then
    local len = sizeof(val)
    return encode_integer(0x40, len) .. ffi.string(val, len)
  end
  error 'Can not encode arbitrary cdata value'
end

encoders.table = function (tab)
  local is_array = true
  local key
  while true do
    local next_key = next(tab, key)
    if not next_key then break end
    if not key then key = 0 end
    is_array = is_array and next_key == key + 1
    key = next_key
  end
  if is_array then
    local len = #tab
    local parts = { encode_integer(0x80, len) }
    for i = 1, len do
      parts[i + 1] = encode(tab[i])
    end
    return concat(parts)
  else
    local parts = {}
    local count = 0
    for k, v in pairs(tab) do
      count = count + 1
      parts[count * 2 - 1] = encode(k)
      parts[count * 2] = encode(v)
    end
    return encode_integer(0xa0, count) .. concat(parts)
  end
end

local decoders = {}
local function decode(chunk, index)
  index = index or 1
  local first = byte(chunk, index)
  local major = rshift(first, 5)
  local minor = band(first, 0x1f)
  return decoders[major](minor, chunk, index + 1)
end

local function decode_u16(chunk, index)
  return bor(
    lshift(byte(chunk, index), 8),
    byte(chunk, index + 1)
  ), index + 2
end

local function decode_u32(chunk, index)
  return bor(
    lshift(byte(chunk, index), 24),
    lshift(byte(chunk, index + 1), 16),
    lshift(byte(chunk, index + 2), 8),
    byte(chunk, index + 3)
  ), index + 4
end

local function decode_u64(chunk, index)
  return bor(
    lshift(u64(byte(chunk, index)), 56),
    lshift(u64(byte(chunk, index + 1)), 48),
    lshift(u64(byte(chunk, index + 2)), 40),
    lshift(u64(byte(chunk, index + 3)), 32),
    lshift(u64(byte(chunk, index + 4)), 24),
    lshift(u64(byte(chunk, index + 5)), 16),
    lshift(u64(byte(chunk, index + 6)), 8),
    u64(byte(chunk, index + 7))
  ), index + 8
end

local function major0(minor, chunk, index)
  if minor < 24 then
    return minor, index
  elseif minor == 24 then
    return byte(chunk, index), index + 1
  elseif minor == 25 then
    return decode_u16(chunk, index)
  elseif minor == 26 then
    return decode_u32(chunk, index)
  elseif minor == 27 then
    return decode_u64(chunk, index)
  else
    error 'Unexpected minor value'
  end
end
decoders[0] = major0

decoders[1] = function (minor, chunk, index)
  if minor < 24 then
    return -minor - 1, index
  elseif minor == 24 then
    return -byte(chunk, index) - 1, index + 1
  elseif minor == 25 then
    return -decode_u16(chunk, index) - 1, index + 2
  elseif minor == 26 then
    return -decode_u32(chunk, index) - 1, index + 4
  elseif minor == 27 then
    return -decode_u64(chunk, index) - 1, index + 8
  else
    error 'Unexpected minor value'
  end
end

decoders[2] = function (minor, chunk, index)
  local len
  len, index = major0(minor, chunk, index)
  return buf(len, sub(chunk, index, index + len - 1)), index + len
end

decoders[3] = function (minor, chunk, index)
  local len
  len, index = major0(minor, chunk, index)
  return sub(chunk, index, index + len - 1), index + len
end

decoders[4] = function (minor, chunk, index)
  local len
  len, index = major0(minor, chunk, index)
  local parts = {}
  for i = 1, len do
    local val
    val, index = decode(chunk, index)
    parts[i] = val
  end
  return parts, index
end

decoders[5] = function (minor, chunk, index)
  local len
  len, index = major0(minor, chunk, index)
  local parts = {}
  for _ = 1, len do
    local key
    key, index = decode(chunk, index)
    local val
    val, index = decode(chunk, index)
    parts[key] = val
  end
  return parts, index
end

decoders[6] = function (minor, chunk, index)
  local value, tag
  tag, index = major0(minor, chunk, index)
  value, index = decode(chunk, index)
  return assert(tags[tag], "Unknown tag encountered")(value), index
end

decoders[7] = function (minor, _, index)
  if minor == 20 then
    return false, index
  elseif minor == 21 then
    return true, index
  elseif minor == 22 then
    return nil, index
  else
    error 'Unexpected minor value'
  end
end

return {
  u64 = u64,
  buf = buf,
  bin = bin,
  registerTag = registerTag,
  encode = encode,
  decode = decode,
}

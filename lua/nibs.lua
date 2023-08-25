local ffi = require 'ffi'
local typeof = ffi.typeof
local cast = ffi.cast
local sizeof = ffi.sizeof
local istype = ffi.istype
local ffi_string = ffi.string
local copy = ffi.copy

local U8Ptr = typeof "uint8_t*"
local U16Ptr = typeof "uint16_t*"
local U32Ptr = typeof "uint32_t*"
local U64Ptr = typeof "uint64_t*"

local U8Arr = typeof "uint8_t[?]"

local I8 = typeof "int8_t"
local I16 = typeof "int16_t"
local I32 = typeof "int32_t"
local I64 = typeof "int64_t"
local U8 = typeof "uint8_t"
local U16 = typeof "uint16_t"
local U32 = typeof "uint32_t"
local U64 = typeof "uint64_t"

local bit = require 'bit'
local rshift = bit.rshift
local lshift = bit.lshift
local bor = bit.bor
local bxor = bit.bxor
local band = bit.band

local char = string.char
local byte = string.byte

ffi.cdef[[
  #pragma pack(1)
  struct nibs_pair {
    unsigned int tag:4;
    unsigned int u4:4;
    union {
      uint8_t u8;
      uint16_t u16;
      uint32_t u32;
      uint64_t u64;
    };
  };
]]
local NibsPairPtr = ffi.typeof "struct nibs_pair*"

-- Main types
local ZIGZAG    = 0x0 -- big = zigzag encoded i64
local FLOAT     = 0x1 -- big = binary encoding of float
local SIMPLE    = 0x2 -- big = subtype (false, true, null, ...)
local REF       = 0x3 -- big = reference offset into Scope
-- slots 4-7 reserved
-- Prefixed length types.
local BYTES     = 0x8 -- big = len (raw octets)
local UTF8      = 0x9 -- big = len (utf-8 encoded unicode string)
local HEXSTRING = 0xa -- big = len (lowercase hex string stored as binary)
local LIST      = 0xb -- big = len (list of nibs values)
local MAP       = 0xc -- big = len (list of alternating nibs keys and values)
local ARRAY     = 0xd -- big = len (array index then list)
                      -- small2 = width, big2 = count
local TRIE      = 0xe -- big = len (trie index then map)
                      -- small2 = width, big2 = count
local SCOPE     = 0xf -- big = len (wrapped value, then array of refs)

-- Simple subtypes
local FALSE = 0
local TRUE  = 1
local NULL  = 2

---@class Nibs.List
local List = {
  __name = "Nibs.List",
  __is_array_like = true,
}

---@class Nibs.Map
local Map = {
  __name = "Nibs.Map",
  __is_array_like = false,
}

---@class Nibs.Array
local Array = {
  __name = "Nibs.List",
  __is_array_like = true,
  __is_indexed = true,
}

---@class Nibs.Trie
local Trie = {
  __name = "Nibs.Trie",
  __is_array_like = false,
  __is_indexed = true,
}

---@class Nibs
local Nibs = {}

local parse_any

--- Convert an I64 to a normal number if it's in the safe range
---@param n integer cdata I64
---@return integer|number maybeNum
local function to_number_maybe(n)
  return (n <= 0x1fffffffffffff and n >= -0x1fffffffffffff)
      and tonumber(n)
      or n
end

---Convert an unsigned 64 bit integer to a signed 64 bit integer using zigzag decoding
---@param num integer
---@return integer
local function decode_zigzag(num)
  local i = I64(num)
  ---@diagnostic disable-next-line: param-type-mismatch
  local o = bxor(rshift(i, 1), -band(i, 1))
  return to_number_maybe(o)
end

local converter = ffi.new 'union {double f;uint64_t i;}'

--- Convert an unsigned 64 bit integer to a double precision floating point by casting the bits
---@param val integer
---@return number
local function decode_float(val)
  converter.i = val
  return converter.f
end

---@param val integer
---@return true|false|nil val_decoded
local function decode_simple(val)
  if val == NULL then
    return nil
  elseif val == FALSE then
    return false
  elseif val == TRUE then
    return true
  else
    error(string.format("Invalid simple tag %d", val))
  end
end

---@param val integer
---@param scope? Nibs.Array
local function decode_ref(val, scope)
  assert(scope)
  return scope[val + 1]
end

local function decode_bytes(data, offset, len)
  local buf = U8Arr(len)
  copy(buf, data+offset, len)
  return buf
end

local function decode_utf8(data, offset, len)
  return ffi_string(data + offset, len)
end

-- Convert a nibble to an ascii hex digit
---@param b integer nibble value
---@return integer ascii hex code
local function to_hex_code(b)
  return b + (b < 10 and 0x30 or 0x57)
end

local function decode_hexstring(data, offset, len)
  local size = lshift(len, 1)
  local buf = U8Arr(size)
  for i = 0, size - 1, 2 do
    local c = data[offset]
    offset = offset + 1
    buf[i] = to_hex_code(rshift(c, 4))
    buf[i + 1] = to_hex_code(band(c, 0xf))
  end
  return ffi_string(buf, size)
end

---@param data integer[]
---@param offset integer
---@param last integer
---@return integer new_offset
---@return integer small
---@return integer big
function Nibs.parse_pair(data, offset, last)
  assert(offset < last)
  ---@type {u4:integer,tag:integer,u8:integer,u16:integer,u32:integer,u64:integer}
  local pair = cast(NibsPairPtr, data + offset)
  local small = pair.u4
  if pair.tag < 12 then
    return offset + 1, small, pair.tag
  elseif pair.tag == 12 then
    assert(offset + 1 < last)
    return offset + 2, small, pair.u8
  elseif pair.tag == 13 then
    assert(offset + 2 < last)
    return offset + 3, small, pair.u16
  elseif pair.tag == 14 then
    assert(offset + 4 < last)
    return offset + 5, small, pair.u32
  else
    assert(offset + 8 < last)
    return offset + 9, small, pair.u64
  end
end
local parse_pair = Nibs.parse_pair

-- Skip a nibs value
---@param data integer[]
---@param offset integer
---@param last integer
---@return integer new_offset
local function skip_value(data, offset, last)
  local small, big
  offset, small, big = parse_pair(data, offset, last)
  offset = (small < 8) and offset or (offset + big)
  assert(offset <= last)
  return offset
end

-- Skip a nibs index
---@param data integer[]
---@param offset integer
---@param last integer
---@return integer new_offset
local function skip_index(data, offset, last)
  local small, big
  offset, small, big = parse_pair(data, offset, last)
  offset = offset + small * big
  assert(offset <= last)
  return offset
end

---@generic T : Nibs.List|Nibs.Array
---@param data integer[]
---@param offset integer
---@param last integer
---@param scope? Nibs.Array
---@param meta T
---@return T
local function parse_list(data, offset, last, scope, meta)
  local list = setmetatable({}, meta)
  local i = 0
  while offset < last do
    local value
    offset, value = parse_any(data, offset, last, scope)
    i = i + 1
    rawset(list, i, value)
  end
  return list
end

---@generic T : Nibs.Map|Nibs.Trie
---@param data integer[]
---@param offset integer
---@param last integer
---@param scope? Nibs.Array
---@param meta T
---@return T
local function parse_map(data, offset, last, scope, meta)
  local map = setmetatable({}, meta)
  while offset < last do
    local key, value
    offset, key = parse_any(data, offset, last, scope)
    offset, value = parse_any(data, offset, last, scope)
    rawset(map, key, value)
  end
  return map
end

---@param data integer[]
---@param offset integer
---@param last integer
---@param scope? Nibs.Array
local function parse_scope(data, offset, last, scope)
  local value_end = skip_value(data, offset, last)
  scope = parse_list(data, skip_index(data, value_end, last), last, scope, Array)
  local value
  offset, value = parse_any(data, offset, value_end, scope)
  assert(offset == value_end)
  return value
end

---@param data integer[]
---@param offset integer
---@param last integer
---@param scope? Nibs.Array
---@return integer new_offset
---@return any? value
function Nibs.parse_any(data, offset, last, scope)
  local small, big
  offset, small, big = parse_pair(data, offset, last)

  -- Inline Types
  if small == ZIGZAG then
    return offset, decode_zigzag(big)
  elseif small == FLOAT then
    return offset, decode_float(big)
  elseif small == SIMPLE then
    return offset, decode_simple(big)
  elseif small == REF then
    return offset, decode_ref(big, scope)
  end

  -- Container Types
  assert(offset + big <= last)
  last = offset + big
  if small == BYTES then
    return last, decode_bytes(data, offset, big)
  elseif small == UTF8 then
    return last, decode_utf8(data, offset, big)
  elseif small == HEXSTRING then
    return last, decode_hexstring(data, offset, big)
  elseif small == LIST then
    return last, parse_list(data, offset, last, scope, List)
  elseif small == MAP then
    return last, parse_map(data, offset, last, scope, Map)
  elseif small == ARRAY then
    return last, parse_list(data, skip_index(data, offset, last), last, scope, Array)
  elseif small == TRIE then
    return last, parse_map(data, skip_index(data, offset, last), last, scope, Trie)
  elseif small == SCOPE then
    return last, parse_scope(data, offset, last)
  end
  error(string.format("Unknown type tag: 0x%x", small))
end
parse_any = Nibs.parse_any

---@param nibs string|ffi.cdata* binary nibs data
---@return any? value
---@return string? error
function Nibs.decode(nibs)
  local t = type(nibs)
  local len
  if t == "string" then
    len = #nibs
  elseif t == "cdata" then
    ---@cast nibs ffi.cdata*
    len = assert(sizeof(nibs))
  else
    error "Input must be string or cdata"
  end
  local data = cast(U8Ptr, nibs)
  local offset, value = parse_any(data, 0, len)
  assert(offset == len)
  return value
end

return Nibs

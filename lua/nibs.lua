local dump = require('deps/pretty-print').dump

local Tibs = require 'tibs'
local ByteWriter = Tibs.ByteWriter


local ffi = require 'ffi'
local typeof = ffi.typeof
local cast = ffi.cast
local sizeof = ffi.sizeof
local istype = ffi.istype
local ffi_string = ffi.string

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
-- slot e reserved
local SCOPE     = 0xf -- big = len (wrapped value, then array of refs)

-- Simple subtypes
local FALSE = 0
local TRUE  = 1
local NULL  = 2

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


---@param data integer[]
---@param offset integer
---@param len integer
---@return integer new_offset
---@return integer small
---@return integer big
function Nibs.parse_pair(data, offset, len)
  assert(offset < len)
  ---@type {u4:integer,tag:integer,u8:integer,u16:integer,u32:integer,u64:integer}
  local pair = cast(NibsPairPtr, data + offset)
  p {
    u4=pair.u4,
    tag=pair.tag,
    u8=pair.u8,
    u16=pair.u16,
    u32=pair.u32,
    u64=pair.u64
  }
  local small = pair.u4
  if pair.tag < 12 then
    return offset + 1, small, pair.tag
  elseif pair.tag == 12 then
    assert(offset + 1 < len)
    return offset + 2, small, pair.u8
  elseif pair.tag == 13 then
    assert(offset + 2 < len)
    return offset + 3, small, pair.u16
  elseif pair.tag == 14 then
    assert(offset + 4 < len)
    return offset + 5, small, pair.u32
  else
    assert(offset + 8 < len)
    return offset + 9, small, pair.u64
  end
end
local parse_pair = Nibs.parse_pair

---@param data integer[]
---@param offset integer
---@param scope_offset integer?
---@param small integer
---@param big integer
---@return integer new_offset
---@return any? value
function Nibs.parse_any(data, offset, scope_offset, small, big)
  p{data=data,offset=offset,scope_offset=scope_offset,small=small,big=big}
  if small == ZIGZAG then
    return offset, decode_zigzag(big)
  elseif small == FLOAT then
    return offset, decode_float(big)
  elseif small == SIMPLE then
    return offset, decode_simple(big)
  elseif small == REF then
    error "TODO: REF"
  elseif small == BYTES then
    error "TODO: BYTES"
  elseif small == UTF8 then
    error "TODO: UTF8"
  elseif small == HEXSTRING then
    error "TODO: HEXSTRING"
  elseif small == LIST then
    error "TODO: LIST"
  elseif small == MAP then
    error "TODO: MAP"
  elseif small == ARRAY then
    error "TODO: ARRAY"
  elseif small == SCOPE then
    error "TODO: SCOPE"
  end
  error(string.format("Unknown type tag: 0x%x", small))
end
parse_any = Nibs.parse_any

---@param nibs string|ffi.cdata* binary nibs data
---@param filename? string
---@return any? value
---@return string? error
function Nibs.decode(nibs, filename)
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
  local offset, small, big = parse_pair(data, 0, len)
  local value
  offset, value = parse_any(data, offset, nil, small, big)
  if offset < 0 then
    return nil, format_syntax_error(nibs, -offset, filename)
  else
    return value
  end
end

return Nibs

local ffi = require 'ffi'
local sizeof = ffi.sizeof
local copy = ffi.copy
local cast = ffi.cast
local ffi_string = ffi.string
local typeof = ffi.typeof
local istype = ffi.istype

local bit = require 'bit'
local lshift = bit.lshift
local rshift = bit.rshift
local bor = bit.bor
local band = bit.band
local bxor = bit.bxor
local arshift = bit.arshift

local char = string.char
local byte = string.byte

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
local FALSE     = 0
local TRUE      = 1
local NULL      = 2

local U8Ptr = typeof "uint8_t*"
local U8Arr = typeof "uint8_t[?]"
local U16Arr = typeof "uint16_t[?]"
local U32Arr = typeof "uint32_t[?]"
local U64Arr = typeof "uint64_t[?]"
local I8 = typeof "int8_t"
local I16 = typeof "int16_t"
local I32 = typeof "int32_t"
local I64 = typeof "int64_t"
local U8 = typeof "uint8_t"
local U16 = typeof "uint16_t"
local U32 = typeof "uint32_t"
local U64 = typeof "uint64_t"

---@class ByteWriter
---@field capacity integer
---@field size integer
---@field data integer[]
local ByteWriter = { __name = "ByteWriter" }
ByteWriter.__index = ByteWriter

---@param initial_capacity? integer
---@return ByteWriter
function ByteWriter.new(initial_capacity)
  initial_capacity = initial_capacity or 128
  return setmetatable({
    capacity = initial_capacity,
    size = 0,
    data = U8Arr(initial_capacity)
  }, ByteWriter)
end

---@param needed integer
function ByteWriter:ensure(needed)
  if needed <= self.capacity then return end
  repeat
    self.capacity = lshift(self.capacity, 1)
  until needed <= self.capacity
  local new_data = U8Arr(self.capacity)
  copy(new_data, self.data, self.size)
  self.data = new_data
end

---@param str string
function ByteWriter:write_string(str)
  local len = #str
  self:ensure(self.size + len)
  copy(self.data + self.size, str, len)
  self.size = self.size + len
end

---@param bytes integer[]|ffi.cdata*
---@param len? integer
function ByteWriter:write_bytes(bytes, len)
  len = len or assert(sizeof(bytes))
  self:ensure(self.size + len)
  copy(self.data + self.size, cast(U8Ptr, bytes), len)
  self.size = self.size + len
end

function ByteWriter:to_string()
  return ffi_string(self.data, self.size)
end

function ByteWriter:to_bytes()
  local buf = U8Arr(self.size)
  copy(buf, self.data, self.size)
  return buf
end

---@class Map
local Map = {
  __name = "Map",
  __is_array_like = false,
}

local KEYS = {}
local VALUES = {}

function Map.new(...)
  local map = setmetatable({}, Map)
  local len = select("#", ...)
  if len > 0 then
    local keys = {}
    local values = {}
    for i = 1, len, 2 do
      local key = select(i, ...)
      local value = select(i + 1, ...)
      keys[#keys + 1] = key
      values[key] = value
    end
    rawset(map, KEYS, keys)
    rawset(map, VALUES, values)
  end
  return map
end

function Map:__newindex(key, value)
  if value == nil then
    local values = rawget(self, VALUES)
    if not values then return end
    if values[key] ~= nil then
      local keys = rawget(self, KEYS)
      if not keys then return end
      for i, k in ipairs(keys) do
        if k == key then
          table.remove(keys, i)
          break
        end
      end
    end
    return
  end
  local values = rawget(self, VALUES)
  if not values then
    values = {}
    rawset(self, VALUES, values)
  end
  local keys = rawget(self, KEYS)
  if not keys then
    keys = {}
    rawset(self, KEYS, keys)
  end
  keys[#keys + 1] = key
  rawset(values, key, value)
end

function Map:__index(key)
  local values = rawget(self, VALUES)
  if not values then return nil end
  return rawget(values, key)
end

function Map:__pairs()
  local keys = rawget(self, KEYS)
  if not keys then return function () end end
  local values = rawget(self, VALUES)

  local i = 0
  local len = #keys
  return function ()
    if i < len then
      i = i + 1
      local key = keys[i]
      return key, rawget(values, key)
    end
  end
end

---@class List
local List = {
  __name = "List",
  __is_array_like = true,
}

---@class Array
local Array = {
  __name = "Array",
  __is_array_like = true,
  __is_indexed = true,
}

---@class Trie
local Trie = {
  __name = "Trie",
  __is_array_like = false,
  __is_indexed = true,
}

---@class Scope
local Scope = {
  __name = "Scope",
  __is_array_like = true,
  __is_indexed = true,
  __is_scope = true,
}

---@class Ref
local Ref = {
  __name = "Ref",
  __is_ref = true,
}

---@class Tibs
local Tibs = {}

---@alias LexerSymbols "{"|"}"|"["|"]"|":"|","|"("|")
---@alias LexerToken "string"|"number"|"bytes"|"true"|"false"|"null"|"nan"|"inf"|"-inf"|"ref"|"error"|"eos"|LexerSymbols

-- Consume a sequence of zero or more digits [0-9]
---@param data integer[]
---@param offset integer
---@param len integer
---@return integer new_offset
local function consume_digits(data, offset, len)
  while offset < len do
    local c = data[offset]
    if c < 0x30 or c > 0x39 then break end -- outside "0-9"
    offset = offset + 1
  end
  return offset
end

-- Consume a single optional character
---@param data integer[]
---@param offset integer
---@param len integer
---@param c1 integer
---@param c2? integer
---@return integer new_offset
---@return boolean did_match
local function consume_optional(data, offset, len, c1, c2)
  if offset < len then
    local c = data[offset]
    if c == c1 or c == c2 then
      offset = offset + 1
      return offset, true
    end
  end
  return offset, false
end

---@param data integer[]
---@param offset integer
---@param len integer
---@return integer offset
---@return LexerToken token
---@return integer token_start
local function next_token(data, offset, len)
  while offset < len do
    local c = data[offset]
    if c == 0x0d or c == 0x0a or c == 0x09 or c == 0x20 then
      -- "\r" | "\n" | "\t" | " "
      -- Skip whitespace
      offset = offset + 1
    elseif c == 0x2f and offset < len and data[offset] == 0x2f then
      -- '//'
      -- Skip comments
      offset = offset + 2
      while offset < len do
        c = data[offset]
        offset = offset + 1
        if c == 0x0d or c == 0x0a then -- "\r" | "\n"
          break
        end
      end
    elseif c == 0x5b or c == 0x5d or c == 0x7b or c == 0x7d or c == 0x3a or c == 0x2c or c == 0x28 or c == 0x29 then
      -- "[" | "]" "{" | "}" | ":" | "," | "(" | ")"
      -- Pass punctuation through as-is
      local start = offset
      offset = offset + 1
      if (c == 0x5b or c == 0x7b) and offset < len and data[offset] == 0x23 then -- "[#"|"{#"
        offset = offset + 1
      end
      return offset, char(c), start
    elseif c == 0x74 and offset + 3 < len -- "t"
        and data[offset + 1] == 0x72      -- "r"
        and data[offset + 2] == 0x75      -- "u"
        and data[offset + 3] == 0x65 then -- "e"
      offset = offset + 4
      return offset, "true", offset - 4
    elseif c == 0x66 and offset + 4 < len -- "f"
        and data[offset + 1] == 0x61      -- "a"
        and data[offset + 2] == 0x6c      -- "l"
        and data[offset + 3] == 0x73      -- "s"
        and data[offset + 4] == 0x65 then -- "e"
      offset = offset + 5
      return offset, "false", offset - 5
    elseif c == 0x6e and offset + 3 < len -- "n"
        and data[offset + 1] == 0x75      -- "u"
        and data[offset + 2] == 0x6c      -- "l"
        and data[offset + 3] == 0x6c then -- "l"
      offset = offset + 4
      return offset, "null", offset - 4
    elseif c == 0x6e and offset + 2 < len -- "n"
        and data[offset + 1] == 0x61      -- "a"
        and data[offset + 2] == 0x6e then -- "n"
      offset = offset + 3
      return offset, "nan", offset - 3
    elseif c == 0x69 and offset + 2 < len -- "i"
        and data[offset + 1] == 0x6e      -- "n"
        and data[offset + 2] == 0x66 then -- "f"
      offset = offset + 3
      return offset, "inf", offset - 3
    elseif c == 0x2d and offset + 3 < len -- "-"
        and data[offset + 1] == 0x69      -- "i"
        and data[offset + 2] == 0x6e      -- "n"
        and data[offset + 3] == 0x66 then -- "f"
      offset = offset + 4
      return offset, "-inf", offset - 4
    elseif c == 0x22 then -- double quote
      -- Parse Strings
      local start = offset
      offset = offset + 1
      while offset < len do
        c = data[offset]
        if c == 0x22 then -- double quote
          offset = offset + 1
          return offset, "string", start
        elseif c == 0x5c then              -- backslash
          offset = offset + 2
        elseif c == 0x0d or c == 0x0a then -- "\r" | "\n"
          -- newline is not allowed
          break
        else -- other characters
          offset = offset + 1
        end
      end
      return offset, "error", offset
    elseif c == 0x2d                      -- "-"
        or (c >= 0x30 and c <= 0x39) then -- "0"-"9"
      local start = offset
      offset = offset + 1
      offset = consume_digits(data, offset, len)
      local matched
      offset, matched = consume_optional(data, offset, len, 0x2e) -- "."
      if matched then
        offset = consume_digits(data, offset, len)
      end
      offset, matched = consume_optional(data, offset, len, 0x45, 0x65) -- "e"|"E"
      if matched then
        offset = consume_optional(data, offset, len, 0x2b, 0x2d)        -- "+"|"-"
        offset = consume_digits(data, offset, len)
      end
      return offset, "number", start
    elseif c == 0x3c then -- "<"
      local start = offset
      offset = offset + 1
      while offset < len do
        c = data[offset]
        if c == 0x09 or c == 0x0a or c == 0x0d or c == 0x20 then -- "\t" | "\n" | "\r" | " "
          offset = offset + 1
          -- Skip whitespace
        elseif (c >= 0x30 and c <= 0x39)
            or (c >= 0x41 and c <= 0x41)
            or (c >= 0x61 and c <= 0x66) then
          -- hex digit
          offset = offset + 1
        elseif c == 0x3e then -- ">"
          offset = offset + 1
          return offset, "bytes", start
        else
          break
        end
      end
      return offset, "error", offset
    elseif c == 0x26 then -- "&" then
      -- parse refs
      local start = offset
      offset = offset + 1
      if offset > len then
        return offset, "error", offset
      else
        offset = consume_digits(data, offset, len)
        return offset, "ref", start
      end
    else
      return offset, "error", offset
    end
  end
  return offset, "eos", offset
end

Tibs.next_token = next_token

local function is_cdata_integer(val)
  return istype(I64, val) or
      istype(I32, val) or
      istype(I16, val) or
      istype(I8, val) or
      istype(U64, val) or
      istype(U32, val) or
      istype(U16, val) or
      istype(U8, val)
end

local any_to_tibs

---@param writer ByteWriter
---@param val any[]
---@param opener string
---@param closer string
local function list_to_tibs(writer, val, opener, closer)
  writer:write_string(opener)
  for i, v in ipairs(val) do
    if i > 1 then
      writer:write_string(",")
    end
    any_to_tibs(writer, v)
  end
  writer:write_string(closer)
end

---@param writer ByteWriter
---@param val table<any,any>
local function map_to_tibs(writer, val, opener)
  writer:write_string(opener)
  local need_comma = false
  for k, v in pairs(val) do
    if need_comma then
      writer:write_string(",")
    end
    need_comma = true
    any_to_tibs(writer, k)
    writer:write_string(":")
    any_to_tibs(writer, v)
  end
  writer:write_string('}')
end

local function bytes_to_tibs(writer, val)
  local size = sizeof(val)
  local bytes = cast(U8Ptr, val)
  writer:write_string("<")
  for i = 0, size - 1 do
    writer:write_string(string.format("%02x", bytes[i]))
  end
  writer:write_string(">")
end

local json_escapes = {
  [0x08] = "\\b",
  [0x09] = "\\t",
  [0x0a] = "\\n",
  [0x0c] = "\\f",
  [0x0d] = "\\r",
  [0x22] = "\\\"",
  [0x2f] = "\\/",
  [0x5c] = "\\\\",
}

local function escape_char(c)
  return json_escapes[c] or string.format("\\u%04x", c)
end

local function string_to_tibs(writer, str)
  local is_plain = true
  for i = 1, #str do
    if byte(str, i) < 0x20 or byte(str, i) > 0x7e then
      is_plain = false
      break
    end
  end
  if is_plain then
    writer:write_string('"')
    writer:write_string(str)
    return writer:write_string('"')
  end
  writer:write_string('"')
  local ptr = cast(U8Ptr, str)
  local start = 0
  local len = #str
  for i = 0, len - 1 do
    local c = ptr[i]
    if c < 0x20 or c > 0x7e then
      print("flush", start, i)
      if i > start then
        writer:write_bytes(ptr + start, i-start)
      end
      start = i + 1
      writer:write_string(escape_char(c))
    end
  end
  if len > start then
    print("flush", start, len)
    writer:write_bytes(ptr + start, len-start)
  end
  return writer:write_string('"')
end

---@param writer ByteWriter
---@param val any
function any_to_tibs(writer, val)
  local mt = getmetatable(val)
  if mt then
    if mt.__is_ref then
      writer:write_string("&")
      writer:write_string(tostring(val[1]))
      return
    elseif mt.__is_scope then
      return list_to_tibs(writer, val, "(", ")")
    elseif mt.__is_array_like == true then
      if mt.__is_indexed then
        return list_to_tibs(writer, val, "[#", "]")
      else
        return list_to_tibs(writer, val, "[", "]")
      end
    elseif mt.__is_array_like == false then
      if mt.__is_indexed then
        return map_to_tibs(writer, val, '{#')
      else
        return map_to_tibs(writer, val, "{")
      end
    end
  end
  local kind = type(val)
  if kind == "cdata" then
    if is_cdata_integer(val) then
      writer:write_string(tostring(val):gsub("[IUL]+", ""))
    else
      return bytes_to_tibs(writer, val)
    end
  elseif kind == "table" then
    local i = 0
    local is_array = true
    for k in pairs(val) do
      i = i + 1
      if k ~= i then
        is_array = false
        break
      end
    end
    if is_array then
      return list_to_tibs(writer, val, "[", "]")
    else
      return map_to_tibs(writer, val)
    end
  elseif kind == "string" then
    string_to_tibs(writer, val)
  elseif kind == "number" then
    if val ~= val then
      writer:write_string("nan")
    elseif val == math.huge then
      writer:write_string("inf")
    elseif val == -math.huge then
      writer:write_string("-inf")
    elseif tonumber(I64(val)) == val then
      local int_str = tostring(I64(val))
      writer:write_string(int_str:sub(1,-3))
    else
      writer:write_string(tostring(val))
    end
  else
    writer:write_string(tostring(val))
  end
end

---@param val any
---@return string
function Tibs.encode(val)
  local writer = ByteWriter.new(0x10000)
  any_to_tibs(writer, val)
  return writer:to_string()
end

---@alias Bytes integer[] cdata uint8_t[?]
---@alias Value List|Map|Array|Trie|Bytes|number|integer|string|boolean|nil

---@param c integer
---@return boolean
local function is_hex_char(c)
  return (c <= 0x39 and c >= 0x30)
      or (c <= 0x66 and c >= 0x61)
      or (c >= 0x41 and c <= 0x46)
end

--- Convert ascii hex digit to integer
--- Assumes input is valid character [0-9a-fA-F]
---@param c integer ascii code for hex digit
---@return integer num value of hex digit (0-15)
local function from_hex_char(c)
  return c - (c <= 0x39 and 0x30
    or c >= 0x61 and 0x57
    or 0x37)
end

local highPair = nil
---@param c integer
local function utf8_encode(c)
  -- Encode surrogate pairs as a single utf8 codepoint
  if highPair then
    local lowPair = c
    c = ((highPair - 0xd800) * 0x400) + (lowPair - 0xdc00) + 0x10000
  elseif c >= 0xd800 and c <= 0xdfff then --surrogate pair
    highPair = c
    return
  end
  highPair = nil

  if c <= 0x7f then
    return char(c)
  elseif c <= 0x7ff then
    return char(
      bor(0xc0, rshift(c, 6)),
      bor(0x80, band(c, 0x3f))
    )
  elseif c <= 0xffff then
    return char(
      bor(0xe0, rshift(c, 12)),
      bor(0x80, band(rshift(c, 6), 0x3f)),
      bor(0x80, band(c, 0x3f))
    )
  elseif c <= 0x10ffff then
    return char(
      bor(0xf0, rshift(c, 18)),
      bor(0x80, band(rshift(c, 12), 0x3f)),
      bor(0x80, band(rshift(c, 6), 0x3f)),
      bor(0x80, band(c, 0x3f))
    )
  else
    error "Invalid codepoint"
  end
end

local json_escapes = {
  [0x62] = "\b",
  [0x66] = "\f",
  [0x6e] = "\n",
  [0x72] = "\r",
  [0x74] = "\t",
}

local function parse_advanced_string(data, first, last)
  local writer = ByteWriter.new(last - first)
  local allowHigh
  local start = first + 1
  last = last - 1

  local function flush()
    if first > start then
      writer:write_bytes(data + start, first - start)
    end
    start = first
  end

  local function write_char_code(c)
    local utf8 = utf8_encode(c)
    if utf8 then
      writer:write_string(utf8)
    else
      allowHigh = true
    end
  end

  while first < last do
    allowHigh = false
    local c = data[first]
    if c >= 0xd8 and c <= 0xdf and first + 1 < last then -- Manually handle native surrogate pairs
      flush()
      write_char_code(bor(
        lshift(c, 8),
        data[first + 1]
      ))
      first = first + 2
      start = first
    elseif c == 0x5c then -- "\\"
      flush()
      first = first + 1
      if first >= last then
        writer:write_string "�"
        start = first
        break
      end
      c = data[first]
      if c == 0x75 then -- "u"
        first = first + 1
        -- Count how many hex digits follow the "u"
        local hex_count = (
          (first < last and is_hex_char(data[first])) and (
            (first + 1 < last and is_hex_char(data[first + 1])) and (
              (first + 2 < last and is_hex_char(data[first + 2])) and (
                (first + 3 < last and is_hex_char(data[first + 3])) and (
                  4
                ) or 3
              ) or 2
            ) or 1
          ) or 0
        )
        -- Emit � if there are less than 4
        if hex_count < 4 then
          writer:write_string "�"
          first = first + hex_count
          start = first
        else
          write_char_code(bor(
            lshift(from_hex_char(data[first]), 12),
            lshift(from_hex_char(data[first + 1]), 8),
            lshift(from_hex_char(data[first + 2]), 4),
            from_hex_char(data[first + 3])
          ))
          first = first + 4
          start = first
        end
      else
        local escape = json_escapes[c]
        if escape then
          writer:write_string(escape)
          first = first + 1
          start = first
        else
          -- Other escapes are included as-is
          start = first
          first = first + 1
        end
      end
    else
      first = first + 1
    end
    if highPair and not allowHigh then
      -- If the character after a surrogate pair is not the other half
      -- clear it and decode as �
      highPair = nil
      writer:write_string "�"
    end
  end
  if highPair then
    -- If the last parsed value was a surrogate pair half
    -- clear it and decode as �
    highPair = nil
    writer:write_string "�"
  end
  flush()
  return writer:to_string()
end

--- Parse a JSON string into a lua string
--- @param data integer[]
--- @param first integer
--- @param last integer
--- @return string
local function parse_string(data, first, last)
  -- Quickly scan for any escape characters or surrogate pairs
  for i = first + 1, last - 1 do
    local c = data[i]
    if c == 0x5c or (c >= 0xd8 and c <= 0xdf) then
      return parse_advanced_string(data, first, last)
    end
  end
  -- Return as-is if it's simple
  return ffi_string(data + first + 1, last - first - 2)
end
Tibs.parse_string = parse_string

--- @param data integer[]
--- @param first integer
--- @param last integer
local function is_integer(data, first, last)
  if data[first] == 0x2d then -- "-"
    first = first + 1
  end
  while first < last do
    local c = data[first]
    -- Abort if anything is seen that's not "0"-"9"
    if c < 0x30 or c > 0x39 then return false end
    first = first + 1
  end
  return true
end

--- Convert an I64 to a normal number if it's in the safe range
---@param n integer cdata I64
---@return integer|number maybeNum
local function to_number_maybe(n)
  return (n <= 0x1fffffffffffff and n >= -0x1fffffffffffff)
      and tonumber(n)
      or n
end

-- Parse a JSON number Literal
--- @param data integer[]
--- @param first integer
--- @param last integer
--- @return number num
local function parse_number(data, first, last)
  if is_integer(data, first, last) then
    -- sign is reversed since we need to use the negative range of I64 for full precision
    -- notice that the big value accumulated is always negative.
    local sign = -1LL
    local big = 0LL
    while first < last do
      local c = data[first]
      if c == 0x2d then -- "-"
        sign = 1LL
      else
        big = big * 10LL - I64(data[first] - 0x30)
      end
      first = first + 1
    end

    return to_number_maybe(big * sign)
  else
    return tonumber(ffi_string(data + first, last - first), 10)
  end
end
Tibs.parse_number = parse_number

-- Parse a Tibs Bytes Literal <xx xx ...>
---@param data integer[]
---@param first integer
---@param last integer
---@return integer offset
---@return Bytes? buf
local function parse_bytes(data, first, last)
  local nibble_count = 0
  local i = first + 1
  while i < last - 1 do
    local c = data[i]
    i = i + 1
    if is_hex_char(c) then
      nibble_count = nibble_count + 1
      c = data[i]
      i = i + 1
      if is_hex_char(c) then
        nibble_count = nibble_count + 1
      else
        return i
      end
    end
  end

  if nibble_count % 2 > 0 then
    return i
  end
  local size = rshift(nibble_count, 1)
  local bytes = U8Arr(size)
  local offset = 0
  i = first + 1
  while i < last - 1 do
    local c = data[i]
    i = i + 1
    if is_hex_char(c) then
      local high = lshift(from_hex_char(c), 4)
      c = data[i]
      i = i + 1
      bytes[offset] = bor(high, from_hex_char(c))
      offset = offset + 1
    end
  end

  return last, bytes
end

-- Parse a Tibs Ref Literal
---@param data integer[]
---@param first integer
---@param last integer
---@return Ref
local function parse_ref(data, first, last)
  return setmetatable({ parse_number(data, first + 1, last) }, Ref)
end

-- Format a Tibs Syntax Error
---@param tibs string
---@param error_offset integer?
---@param filename? string
---@return string error
local function format_syntax_error(tibs, error_offset, filename)
  local c = error_offset and char(byte(tibs, error_offset + 1))
  if c then
    local index = error_offset + 1
    local before = string.sub(tibs, 1, index)
    local row = 1
    local offset = 0
    for i = 1, #before do
      if string.byte(before, i) == 0x0a then
        row = row + 1
        offset = i
      end
    end
    local col = index - offset
    return string.format(
      "Tibs syntax error: Unexpected %q (%s:%d:%d)",
      c, filename or "[input string]", row, col
    )
  end
  return "Lexer error: Unexpected EOS"
end
Tibs.format_syntax_error = format_syntax_error

local tibs_parse_any

---@generic T : List|Array|Scope
---@param data integer[]
---@param offset integer
---@param len integer
---@param meta T
---@param closer "]"|")"
---@return integer offset
---@return T? list
local function parse_list(data, offset, len, meta, closer)
  local list = setmetatable({}, meta)
  local token, start, value
  offset, token, start = next_token(data, offset, len)
  local i = 0
  while token ~= closer do
    offset, value = tibs_parse_any(data, offset, len, token, start)
    if offset < 0 then return offset end

    i = i + 1
    list[i] = value

    offset, token, start = next_token(data, offset, len)
    if token == "," then
      offset, token, start = next_token(data, offset, len)
    elseif token ~= closer then
      return -offset
    end
  end

  return offset, list
end

-- Parse a Tibs Map {x:y, ...}
---@generic T : Map|Trie
---@param data integer[]
---@param offset integer
---@param len integer
---@param meta T
---@return integer offset
---@return T? map
local function parse_map(data, offset, len, meta)
  local map = setmetatable({}, meta)
  local token, start, key, value
  offset, token, start = next_token(data, offset, len)
  while token ~= "}" do
    offset, key = tibs_parse_any(data, offset, len, token, start)
    if offset < 0 then return offset end

    offset, token = next_token(data, offset, len)
    if token ~= ":" then return -offset end

    offset, token, start = next_token(data, offset, len)
    offset, value = tibs_parse_any(data, offset, len, token, start)
    if offset < 0 then return offset end

    map[key]=value

    offset, token, start = next_token(data, offset, len)
    if token == "," then
      offset, token, start = next_token(data, offset, len)
    elseif token ~= "}" then
      return -offset
    end
  end

  return offset, map
end

---comment
---@param data integer[]
---@param offset integer
---@param len integer
---@param token LexerToken
---@param start integer
---@return integer offset negative when error
---@return any? value unset when error
function tibs_parse_any(data, offset, len, token, start)
  if token == "number" then
    return offset, parse_number(data, start, offset)
  elseif token == "nan" then
    return offset, 0 / 0
  elseif token == "inf" then
    return offset, 1 / 0
  elseif token == "-inf" then
    return offset, -1 / 0
  elseif token == "true" then
    return offset, true
  elseif token == "false" then
    return offset, false
  elseif token == "null" then
    return offset, nil
  elseif token == "ref" then
    return offset, parse_ref(data, start, offset)
  elseif token == "bytes" then
    return parse_bytes(data, start, offset)
  elseif token == "string" then
    return offset, parse_string(data, start, offset)
  elseif token == "[" then
    if offset - start > 1 then
      return parse_list(data, offset, len, Array, "]")
    else
      return parse_list(data, offset, len, List, "]")
    end
  elseif token == "{" then
    if offset - start > 1 then
      return parse_map(data, offset, len, Trie)
    else
      return parse_map(data, offset, len, Map)
    end
  elseif token == "(" then
    return parse_list(data, offset, len, Scope, ")")
  else
    return -start
  end
end

---@param tibs string
---@param filename? string
---@return any? value
---@return string? error
function Tibs.decode(tibs, filename)
  local data = cast(U8Ptr, tibs)
  local offset = 0
  local len = #tibs
  local token, start
  offset, token, start = next_token(data, offset, len)
  local value
  offset, value = tibs_parse_any(data, offset, len, token, start)
  if offset < 0 then
    return nil, format_syntax_error(tibs, -offset, filename)
  else
    return value
  end
end

ffi.cdef [[
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
  #pragma pack(1)
  struct nibs_pair_4 {
    unsigned int tag:4;
    unsigned int u4:4;
  };
  #pragma pack(1)
  struct nibs_pair_8 {
    unsigned int tag:4;
    unsigned int u4:4;
    uint8_t u8;
  };
  #pragma pack(1)
  struct nibs_pair_16 {
    unsigned int tag:4;
    unsigned int u4:4;
    uint16_t u16;
  };
  #pragma pack(1)
  struct nibs_pair_32 {
    unsigned int tag:4;
    unsigned int u4:4;
    uint32_t u32;
  };
  #pragma pack(1)
  struct nibs_pair_64 {
    unsigned int tag:4;
    unsigned int u4:4;
    uint64_t u64;
  };
]]
local NibsPairPtr = ffi.typeof "struct nibs_pair*"
local Nibs4 = ffi.typeof "struct nibs_pair_4"
local Nibs8 = ffi.typeof "struct nibs_pair_8"
local Nibs16 = ffi.typeof "struct nibs_pair_16"
local Nibs32 = ffi.typeof "struct nibs_pair_32"
local Nibs64 = ffi.typeof "struct nibs_pair_64"


---@class Nibs
local Nibs = {}

local nibs_parse_any

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
  ---@diagnostic disable-next-line: inject-field
  converter.i = val
  ---@diagnostic disable-next-line: undefined-field
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
---@param scope? Array
local function decode_ref(val, scope)
  assert(scope)
  return scope[val + 1]
end

local function decode_bytes(data, offset, len)
  local buf = U8Arr(len)
  copy(buf, data + offset, len)
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

---@generic T : List|Array
---@param data integer[]
---@param offset integer
---@param last integer
---@param scope? Array
---@param meta T
---@return T
local function nibs_parse_list(data, offset, last, scope, meta)
  local list = setmetatable({}, meta)
  local i = 0
  while offset < last do
    local value
    offset, value = nibs_parse_any(data, offset, last, scope)
    i = i + 1
    list[i]=value
  end
  return list
end

---@generic T : Map|Trie
---@param data integer[]
---@param offset integer
---@param last integer
---@param scope? Array
---@param meta T
---@return T
local function nibs_parse_map(data, offset, last, scope, meta)
  local map = setmetatable({}, meta)
  while offset < last do
    local key, value
    offset, key = nibs_parse_any(data, offset, last, scope)
    offset, value = nibs_parse_any(data, offset, last, scope)
    map[key] = value
  end
  return map
end

---@param data integer[]
---@param offset integer
---@param last integer
---@param scope? Array
local function parse_scope(data, offset, last, scope)
  local value_end = skip_value(data, offset, last)
  scope = nibs_parse_list(data, skip_index(data, value_end, last), last, scope, Array)
  local value
  offset, value = nibs_parse_any(data, offset, value_end, scope)
  assert(offset == value_end)
  return value
end

---@param data integer[]
---@param offset integer
---@param last integer
---@param scope? Array
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
    return last, nibs_parse_list(data, offset, last, scope, List)
  elseif small == MAP then
    return last, nibs_parse_map(data, offset, last, scope, Map)
  elseif small == ARRAY then
    return last, nibs_parse_list(data, skip_index(data, offset, last), last, scope, Array)
  elseif small == TRIE then
    return last, nibs_parse_map(data, skip_index(data, offset, last), last, scope, Trie)
  elseif small == SCOPE then
    return last, parse_scope(data, offset, last)
  end
  error(string.format("Unknown type tag: 0x%x", small))
end

nibs_parse_any = Nibs.parse_any

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
  local offset, value = nibs_parse_any(data, 0, len)
  assert(offset == len)
  return value
end

---@param writer ByteWriter
---@param small integer
---@param big integer
local function write_pair(writer, small, big)
  if big < 12 then
    return writer:write_bytes(Nibs4(big, small))
  elseif big < 0x100 then
    return writer:write_bytes(Nibs8(12, small, big))
  elseif big < 0x10000 then
    return writer:write_bytes(Nibs16(13, small, big))
  elseif big < 0x100000000 then
    return writer:write_bytes(Nibs32(14, small, big))
  else
    return writer:write_bytes(Nibs64(15, small, big))
  end
end

---@param big integer
---@return integer size
local function measure_pair(big)
  return big < 10 and 1 or big < 0x100 and 2 or big < 0x10000 and 3 or big < 0x100000000 and 5 or 9
end

--- Convert a signed 64 bit integer to an unsigned 64 bit integer using zigzag encoding
---@param num integer
---@return integer
local function encode_zigzag(num)
  local i = I64(num)
  ---@diagnostic disable-next-line: return-type-mismatch, param-type-mismatch
  return U64(bxor(arshift(i, 63), lshift(i, 1)))
end

--- Convert a double precision floating point to an unsigned 64 bit integer by casting the bits
---@param val number
---@return integer
local function encode_float(val)
  -- Use same NaN encoding as used by V8 JavaScript engine
  if val ~= val then
    return 0x7ff8000000000000ULL
  end
  ---@diagnostic disable-next-line: inject-field
  converter.f = val
  return converter.i
end

---@param writer ByteWriter
---@param int integer|ffi.cdata*
local function write_integer(writer, int)
---@diagnostic disable-next-line: param-type-mismatch
  return write_pair(writer, ZIGZAG, encode_zigzag(int))
end

---@param writer ByteWriter
---@param num number
local function write_float(writer, num)
  return write_pair(writer, FLOAT, encode_float(num))
end

---@param writer ByteWriter
---@param num number
local function write_number(writer, num)
  local inum = I64(num)
  if tonumber(inum) == num then
    return write_integer(writer, inum)
  end
  return write_float(writer, num)
end

--- Convert ascii hex digit to a nibble
--- Assumes input is valid character [0-9a-f]
---@param code integer ascii code for hex digit
---@return integer num value of hex digit (0-15)
local function from_hex_code(code)
  return code - (code >= 0x61 and 0x57 or 0x30)
end

---@param writer ByteWriter
---@param hex string
local function write_hex_string(writer, hex)
  local len = #hex
  local size = rshift(len, 1)
  local buf = U8Arr(size)
  local offset = 0
  for i = 1, len, 2 do
    buf[offset] = bor(
      lshift(from_hex_code(byte(hex, i)), 4),
      from_hex_code(byte(hex, i + 1))
    )
    offset = offset + 1
  end
  write_pair(writer, HEXSTRING, size)
  return writer:write_bytes(buf)
end

---@param writer ByteWriter
---@param str string
local function write_string(writer, str)
  local len = #str
  if len > 0 and len % 2 == 0 and string.match(str, "^[0-9a-f]*$") then
    return write_hex_string(writer, str)
  end
  write_pair(writer, UTF8, len)
  return writer:write_string(str)
end

---@param writer ByteWriter
---@param buf ffi.cdata*
local function write_bytes(writer, buf)
  local size = assert(sizeof(buf))
  write_pair(writer, BYTES, size)
  return writer:write_bytes(buf)
end

local write_any


local widthmap = {
  [1] = U8Arr,
  [2] = U16Arr,
  [4] = U32Arr,
  [8] = U64Arr,
}

---@param indices integer[]
---@return integer width
---@return integer count
---@return ffi.cdata* index `uint8_t[?]`
local function encode_index(indices)
  local max = 0
  local count = #indices
  for i = 1, count do
    max = math.max(max, indices[i])
  end
  local width = max < 0x100 and 1 or max < 0x10000 and 2 or max < 0x100000000 and 4 or 8
  local UArr = assert(widthmap[width])
  local index = UArr(count)
  for i = 1, count do
    index[i - 1] = indices[i]
  end
  return width, count, index
end

---@param writer ByteWriter
---@param list any[]
---@param refmap? table<any,integer>
local function write_list(writer, list, refmap)
  if #list == 0 then
    return write_pair(writer, LIST, 0)
  end
  local subwriter = ByteWriter.new(1024)
  for _, value in ipairs(list) do
    write_any(subwriter, value, refmap)
  end
  write_pair(writer, LIST, subwriter.size)
  return writer:write_bytes(subwriter.data, subwriter.size)
end

---@param writer ByteWriter
---@param list any[]
---@param refmap? table<any,integer>
local function write_array(writer, list, refmap)
  local subwriter = ByteWriter.new(1024)
  ---@type integer[]
  local indices = {}
  for i, value in ipairs(list) do
    indices[i] = subwriter.size
    write_any(subwriter, value, refmap)
  end
  local width, count, index = encode_index(indices)
  local index_size = width * count
  write_pair(writer, ARRAY, measure_pair(count) + index_size + subwriter.size)
  write_pair(writer, width, count)
  writer:write_bytes(index, index_size)
  return writer:write_bytes(subwriter.data, subwriter.size)
end

---@param writer ByteWriter
---@param map table<any,any>
---@param refmap? table<any,integer>
local function write_map(writer, map, refmap)
  local subwriter = ByteWriter.new(1024)
  for key, value in pairs(map) do
    write_any(subwriter, key, refmap)
    write_any(subwriter, value, refmap)
  end
  write_pair(writer, MAP, subwriter.size)
  return writer:write_bytes(subwriter.data, subwriter.size)
end

---@param writer ByteWriter
---@param map table<any,any>
---@param refmap? table<any,integer>
local function write_trie(writer, map, refmap)
  print "TODO: Implement write_trie"
  return write_map(writer, map, refmap)
end

---@param writer ByteWriter
---@param combined_scope any[]
---@param refmap? table<any,integer>
local function write_nested_scope(writer, combined_scope, refmap)
  local subwriter = ByteWriter.new(1024)
  local subrefmap = {}
  ---@type integer[]
  local indices = {}
  for i = 2, #combined_scope do
    local value = combined_scope[i]
    indices[i - 1] = subwriter.size
    subrefmap[value] = i - 2
    write_any(subwriter, value, refmap)
  end

  local subwriter2 = ByteWriter.new(1024)
  write_any(subwriter2, combined_scope[1], subrefmap)

  local width, count, index = encode_index(indices)
  local index_size = width * count
  write_pair(writer, SCOPE, subwriter2.size + measure_pair(count) + index_size + subwriter.size)
  writer:write_bytes(subwriter2.data, subwriter2.size)
  write_pair(writer, width, count)
  writer:write_bytes(index, index_size)
  return writer:write_bytes(subwriter.data, subwriter.size)
end

---@param writer ByteWriter
---@param val any
---@param refmap? table<any,integer>
function write_any(writer, val, refmap)
  local mt = getmetatable(val)
  if mt then
    if mt.__is_ref then
      return write_pair(writer, REF, val[1])
    elseif mt.__is_scope then
      return write_nested_scope(writer, val, refmap)
    elseif mt.__is_array_like == true then
      if mt.__is_indexed then
        return write_array(writer, val, refmap)
      else
        return write_list(writer, val, refmap)
      end
    elseif mt.__is_array_like == false then
      if mt.__is_indexed then
        return write_trie(writer, val, refmap)
      else
        return write_map(writer, val, refmap)
      end
    end
  end
  if refmap then
    local ref_id = refmap[val]
    if ref_id then
      return write_pair(writer, REF, ref_id)
    end
  end
  local kind = type(val)
  if kind == "number" then
    return write_number(writer, val)
  elseif kind == "string" then
    return write_string(writer, val)
  elseif kind == "boolean" then
    return write_pair(writer, SIMPLE, val and TRUE or FALSE)
  elseif kind == "nil" then
    return write_pair(writer, SIMPLE, NULL)
  elseif kind == "cdata" then
    if is_cdata_integer(val) then
      return write_integer(writer, val)
    end
    return write_bytes(writer, val)
  elseif kind == "table" then
    local i = 0
    local is_array = true
    for k in pairs(val) do
      i = i + 1
      if k ~= i then
        is_array = false
        break
      end
    end
    if is_array then
      return write_list(writer, val, refmap)
    else
      return write_map(writer, val, refmap)
    end
  end
  error("Unable to encode type " .. kind)
end

---@param writer ByteWriter
---@param val any
---@param refs any[]
---@return table<any,integer> refmap
local function encode_scope(writer, val, refs)
  error "TODO: encode_scope"
end

---comment
---@param val any
---@param refs? any[]
---@return ffi.cdata*
function Nibs.encode(val, refs)
  local writer = ByteWriter.new(1024)
  write_any(writer, val, refs and encode_scope(writer, val, refs))
  return writer:to_bytes()
end

return {
  ByteWriter = ByteWriter,
  Tibs = Tibs,
  Nibs = Nibs,
  List = List,
  Map = Map,
  Array = Array,
  Trie = Trie,
  Ref = Ref,
  Scope = Scope,
  encode = Nibs.encode,
  decode = Nibs.decode,
}

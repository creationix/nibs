local ByteWriter = require './bytewriter'

local ffi = require 'ffi'
local typeof = ffi.typeof
local cast = ffi.cast
local sizeof = ffi.sizeof
local istype = ffi.istype
local ffi_string = ffi.string

local U8Ptr = typeof "uint8_t*"
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
local band = bit.band

local char = string.char
local byte = string.byte

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

---@class Tibs.Map
local Map = {
  __name = "Map",
  __is_array_like = false,
}
Tibs.Map = Map

---@class Tibs.List
local List = {
  __name = "List",
  __is_array_like = true,
}
Tibs.List = List

---@class Tibs.Array
local Array = {
  __name = "Array",
  __is_array_like = true,
  __is_indexed = true,
}
Tibs.Array = Array

---@class Tibs.Trie
local Trie = {
  __name = "Trie",
  __is_array_like = false,
  __is_indexed = true,
}
Tibs.Trie = Trie

---@class Tibs.Scope
local ScopeMeta = {
  __name = "Scope",
  __is_array_like = true,
  __is_indexed = true,
  __is_scope = true,
}

---@class Tibs.Ref
local RefMeta = {
  __name = "Ref",
  __is_ref = true,
}

local any_to_tibs

---@param slice Tibs.ByteWriter
---@param val any[]
---@param opener string
---@param closer string
local function list_to_tibs(slice, val, opener, closer)
  slice:write_string(opener)
  for i, v in ipairs(val) do
    if i > 1 then
      slice:write_string(",")
    end
    any_to_tibs(slice, v)
  end
  slice:write_string(closer)
end

---@param slice Tibs.ByteWriter
---@param val table<any,any>
local function map_to_tibs(slice, val, opener)
  slice:write_string(opener)
  local need_comma = false
  for k, v in pairs(val) do
    if need_comma then
      slice:write_string(",")
    end
    need_comma = true
    any_to_tibs(slice, k)
    slice:write_string(":")
    any_to_tibs(slice, v)
  end
  slice:write_string('}')
end

local function bytes_to_tibs(slice, val)
  local size = sizeof(val)
  local bytes = cast(U8Ptr, val)
  slice:write_string("<")
  for i = 0, size - 1 do
    slice:write_string(string.format("%02x", bytes[i]))
  end
  slice:write_string(">")
end

---@param slice Tibs.ByteWriter
---@param val any
function any_to_tibs(slice, val)
  local mt = getmetatable(val)
  if mt then
    if mt.__is_ref then
      slice:write_string("&")
      slice:write_string(tostring(val[1]))
      return
    elseif mt.__is_scope then
      return list_to_tibs(slice, val, "(", ")")
    elseif mt.__is_array_like == true then
      if mt.__is_indexed then
        return list_to_tibs(slice, val, "[#", "]")
      else
        return list_to_tibs(slice, val, "[", "]")
      end
    elseif mt.__is_array_like == false then
      if mt.__is_indexed then
        return map_to_tibs(slice, val, '{#')
      else
        return map_to_tibs(slice, val, "{")
      end
    end
  end
  local kind = type(val)
  if kind == "cdata" then
    if is_cdata_integer(val) then
      slice:write_string(tostring(val):gsub("[IUL]+", ""))
    else
      return bytes_to_tibs(slice, val)
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
      return list_to_tibs(slice, val, "[", "]")
    else
      return map_to_tibs(slice, val)
    end
  elseif kind == "string" then
    -- TODO: use proper JSON escaping if it differs from %q
    slice:write_string(string.format("%q", val))
  else
    slice:write_string(tostring(val))
  end
end

---@param val any
---@return string
function Tibs.encode(val)
  local slice = ByteWriter.new(0x10000)
  any_to_tibs(slice, val)
  return slice:to_string()
end

---@alias Tibs.Bytes integer[] cdata uint8_t[?]
---@alias Tibs.Value Tibs.List|Tibs.Map|Tibs.Array|Tibs.Trie|Tibs.Bytes|number|integer|string|boolean|nil

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
---@return Tibs.Bytes? buf
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
---@return Tibs.Ref
local function parse_ref(data, first, last)
  return setmetatable({ parse_number(data, first + 1, last) }, RefMeta)
end

-- Format a Tibs Syntax Error
---@param tibs string
---@param error_offset integer?
---@param filename? string
---@return string error
local function format_syntax_error(tibs, error_offset, filename)
  -- print(debug.traceback("", 2))
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

local parse_any

---@generic T : Tibs.List|Tibs.Array|Tibs.Scope
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
    offset, value = parse_any(data, offset, len, token, start)
    if offset < 0 then return offset end

    i = i + 1
    rawset(list, i, value)

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
---@generic T : Tibs.Map|Tibs.Trie
---@param data integer[]
---@param offset integer
---@param len integer
---@param meta T
---@return integer offset
---@return T? map
local function parse_map(data, offset, len, meta)
  local obj = setmetatable({}, meta)
  local token, start, key, value
  offset, token, start = next_token(data, offset, len)
  while token ~= "}" do
    offset, key = parse_any(data, offset, len, token, start)
    if offset < 0 then return offset end

    offset, token = next_token(data, offset, len)
    if token ~= ":" then return -offset end

    offset, token, start = next_token(data, offset, len)
    offset, value = parse_any(data, offset, len, token, start)
    if offset < 0 then return offset end

    rawset(obj, key, value)

    offset, token, start = next_token(data, offset, len)
    if token == "," then
      offset, token, start = next_token(data, offset, len)
    elseif token ~= "}" then
      return -offset
    end
  end

  return offset, obj
end

---comment
---@param data integer[]
---@param offset integer
---@param len integer
---@param token LexerToken
---@param start integer
---@return integer offset negative when error
---@return any? value unset when error
function parse_any(data, offset, len, token, start)
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
    return parse_list(data, offset, len, ScopeMeta, ")")
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
  offset, value = parse_any(data, offset, len, token, start)
  if offset < 0 then
    return nil, format_syntax_error(tibs, -offset, filename)
  else
    return value
  end
end

return Tibs

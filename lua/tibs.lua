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

---@class Tibs.ByteWriter
---@field capacity integer
---@field size integer
---@field data integer[]
local ByteWriter = { __name = "ByteWriter" }
ByteWriter.__index = ByteWriter

---@param initial_capacity? integer
---@return Tibs.ByteWriter
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
  print("new capacity", self.capacity)
  local new_data = U8Arr(self.capacity)
  ffi.copy(new_data, self.data, self.size)
  self.data = new_data
end

---@param str string
function ByteWriter:write_string(str)
  local len = #str
  self:ensure(self.size + len)
  ffi.copy(self.data + self.size, str, len)
  self.size = self.size + len
end

---@param bytes integer[]|ffi.cdata*
---@param len? integer
function ByteWriter:write_bytes(bytes, len)
  len = len or assert(sizeof(bytes))
  self:ensure(self.size + len)
  ffi.copy(self.data + self.size, cast(U8Ptr, bytes), len)
  self.size = self.size + len
end

function ByteWriter:to_string()
  return ffi_string(self.data, self.size)
end

---@alias LexerSymbols "{"|"}"|"["|"]"|":"|","|"("|")
---@alias LexerToken "string"|"number"|"bytes"|"true"|"false"|"null"|"nan"|"inf"|"-inf"|"ref"|"error"|LexerSymbols

---@param data integer[]
---@param len integer
---@return fun():LexerToken?,integer?,integer?
local function tokenize(data, len)
  local offset = 0

  -- Consume a sequence of zero or more digits [0-9]
  local function consume_digits()
    while offset < len do
      local c = data[offset]
      if c < 0x30 or c > 0x39 then break end -- outside "0-9"
      offset = offset + 1
    end
  end

  -- Consume a single optional character
  ---@param c1 integer
  ---@param c2? integer
  ---@return boolean did_match
  local function consume_optional(c1, c2)
    if offset < len then
      local c = data[offset]
      if c == c1 or c == c2 then
        offset = offset + 1
        return true
      end
    end
    return false
  end

  return function()
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
        if c == 0x5b and offset < len and data[offset] == 0x23 then -- "#"
          offset = offset + 1
        end
        return char(c), start, offset
      elseif c == 0x74 and offset + 3 < len -- "t"
          and data[offset + 1] == 0x72      -- "r"
          and data[offset + 2] == 0x75      -- "u"
          and data[offset + 3] == 0x65 then -- "e"
        offset = offset + 4
        return "true", offset - 4, offset
      elseif c == 0x66 and offset + 4 < len -- "f"
          and data[offset + 1] == 0x61      -- "a"
          and data[offset + 2] == 0x6c      -- "l"
          and data[offset + 3] == 0x73      -- "s"
          and data[offset + 4] == 0x65 then -- "e"
        offset = offset + 5
        return "false", offset - 5, offset
      elseif c == 0x6e and offset + 3 < len -- "n"
          and data[offset + 1] == 0x75      -- "u"
          and data[offset + 2] == 0x6c      -- "l"
          and data[offset + 3] == 0x6c then -- "l"
        offset = offset + 4
        return "null", offset - 4, offset
      elseif c == 0x6e and offset + 2 < len -- "n"
          and data[offset + 1] == 0x61      -- "a"
          and data[offset + 2] == 0x6e then -- "n"
        offset = offset + 3
        return "nan", offset - 3, offset
      elseif c == 0x69 and offset + 2 < len -- "i"
          and data[offset + 1] == 0x6e      -- "n"
          and data[offset + 2] == 0x66 then -- "f"
        offset = offset + 3
        return "inf", offset - 3, offset
      elseif c == 0x2d and offset + 3 < len -- "-"
          and data[offset + 1] == 0x69      -- "i"
          and data[offset + 2] == 0x6e      -- "n"
          and data[offset + 3] == 0x66 then -- "f"
        offset = offset + 4
        return "-inf", offset - 4, offset
      elseif c == 0x22 then -- double quote
        -- Parse Strings
        local start = offset
        offset = offset + 1
        while offset < len do
          c = data[offset]
          if c == 0x22 then -- double quote
            offset = offset + 1
            return "string", start, offset
          elseif c == 0x5c then              -- backslash
            offset = offset + 2
          elseif c == 0x0d or c == 0x0a then -- "\r" | "\n"
            -- newline is not allowed
            break
          else -- other characters
            offset = offset + 1
          end
        end
        return "error", offset, offset
      elseif c == 0x2d                      -- "-"
          or (c >= 0x30 and c <= 0x39) then -- "0"-"9"
        local start = offset
        offset = offset + 1
        consume_digits()
        if consume_optional(0x2e) then -- "."
          consume_digits()
        end
        if consume_optional(0x45, 0x65) then -- "e"|"E"
          consume_optional(0x2b, 0x2d)       -- "+"|"-"
          consume_digits()
        end
        return "number", start, offset
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
            return "bytes", start, offset
          else
            break
          end
        end
        return "error", offset, offset
      elseif c == 0x26 then -- "&" then
        -- parse refs
        local start = offset
        offset = offset + 1
        if offset > len then
          return "error", offset, offset
        else
          consume_digits()
          return "ref", start, offset
        end
      else
        return "error", offset, offset
      end
    end
  end
end

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
local MapMeta = {
  __name = "Map",
  __is_array_like = false,
}

---@class Tibs.List
local ListMeta = {
  __name = "List",
  __is_array_like = true,
}

---@class Tibs.Array
local ArrayMeta = {
  __name = "Array",
  __is_array_like = true,
  __is_indexed = true,
}

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
local function map_to_tibs(slice, val)
  slice:write_string('{')
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
      return map_to_tibs(slice, val)
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
---@alias Tibs.Value Tibs.List|Tibs.Map|Tibs.Array|Tibs.Bytes|number|integer|string|boolean|nil

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
  local start = first

  local function flush()
    if first > start then
      writer:write_bytes(data + start, first - start)
    end
    start = first
  end

  local function write_char_code(c)
    local utf8
    utf8 = utf8_encode(c)
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
    if c == 0x5c or (c >= 0xd8 and c <= 0xdf) then -- "\\"
      return parse_advanced_string(data, first, last)
    end
  end
  return ffi_string(data + first + 1, last - first - 2)
end

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

-- Parse a Tibs Bytes Literal
---@param data integer[]
---@param first integer
---@param last integer
---@return Tibs.Bytes? buf
---@return integer? error_offset
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
        return nil, i
      end
    end
  end

  if nibble_count % 2 > 0 then
    return nil, i
  end
  local size = rshift(nibble_count, 1)
  local bytes = U8Arr(size)
  local offset = 0
  i = first + 1
  -- local parts = {}
  while i < last - 1 do
    local c = data[i]
    i = i + 1
    if is_hex_char(c) then
      local high = lshift(from_hex_char(c), 4)
      c = data[i]
      i = i + 1
      bytes[offset] = bor(high, from_hex_char(c))
      -- parts[#parts + 1] = string.format("%02x", bytes[offset])
      offset = offset + 1
    end
  end
  -- print("bytes", table.concat(parts, " "))
  return bytes
end

-- Parse a Tibs Ref Literal
---@param data integer[]
---@param first integer
---@param last integer
---@return Tibs.Ref? ref
---@return string? error
local function parse_ref(data, first, last)
  local id, err = parse_number(data, first + 1, last)
  if err then return nil, err end
  return (setmetatable({ id }, RefMeta))
end

-- Format a Tibs Syntax Error
---@param tibs string
---@param error_offset integer?
---@param filename? string
---@return nil
---@return string error
local function syntax_error(tibs, error_offset, filename)
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
    return nil, string.format(
      "Tibs syntax error: Unexpected %q (%s:%d:%d)",
      c, filename or "[input string]", row, col
    )
  end
  return nil, "Lexer error: Unexpected EOS"
end


---@param tibs string
---@param filename? string
---@return any? value
---@return string? error
function Tibs.decode(tibs, filename)
  local data = cast(U8Ptr, tibs)
  local len = #tibs
  local _next_token = tokenize(data, len)

  local token, first, last

  -- Consume the next lexer token
  ---@return LexerToken?
  ---@return integer? first
  ---@return integer? last
  local function next_token()
    token, first, last = _next_token()
    -- print(string.format("% 10s % 10d % 10d %s",
    --   token, first, last,
    --   require('deps/pretty-print').colorize("highlight", string.sub(tibs, first + 1, last))
    -- ))
  end



  local parse_value

  -- Parse a Tibs Map
  ---@return Map? map
  ---@return string? error
  local function parse_map()
    local obj = setmetatable({}, MapMeta)
    while token ~= "}" do
      -- Parse key
      local key, value, err
      key, err = parse_value()
      if err then return nil, err end
      if key == nil then return syntax_error(tibs, first, filename) end

      -- Parse colon
      next_token()
      if token ~= ":" then return syntax_error(tibs, first, filename) end

      -- Parse value
      next_token()
      value, err = parse_value()
      if err then return nil, err end
      rawset(obj, key, value)

      -- Parse comma or end
      next_token()
      if token == "}" then break end
      if token == "," then
        next_token()
      else
        return syntax_error(tibs, first, filename)
      end
    end
    return obj
  end

  -- Parse a Tibs List/Array
  ---@param indexed? true
  ---@return (List|Array)? array
  ---@return string? error
  local function parse_list_or_array(indexed)
    local arr = setmetatable({}, indexed and ArrayMeta or ListMeta)
    local length = 0
    while token ~= "]" do
      local value, err = parse_value()
      if err then return nil, err end
      length = length + 1
      rawset(arr, length, value)
      next_token()
      if token == "]" then break end
      if token == "," then
        next_token()
      else
        return syntax_error(tibs, first, filename)
      end
    end
    return arr
  end

  -- Parse a Tibs Scope
  ---@return Tibs.Scope? scope
  ---@return string? error
  local function parse_scope()
    local scope = setmetatable({}, ScopeMeta)
    local length = 0
    while token ~= ")" do
      local value, err = parse_value()
      if err then return nil, err end
      length = length + 1
      rawset(scope, length, value)
      next_token()
      if token == ")" then break end
      if token == "," then
        next_token()
      end
    end
    return scope
  end


  ---@return Value parsed_value
  ---@return nil|string syntax_error
  function parse_value()
    if token == "number" then return parse_number(data, first, last) end
    if token == "nan" then return 0 / 0 end
    if token == "inf" then return 1 / 0 end
    if token == "-inf" then return -1 / 0 end
    if token == "true" then return true end
    if token == "false" then return false end
    if token == "null" then return nil end
    if token == "ref" then return parse_ref(data, first, last) end
    if token == "bytes" then
      local bytes, error_offset = parse_bytes(data, first, last)
      if not bytes then return syntax_error(tibs, error_offset, filename) end
      return bytes
    end
    if token == "string" then return parse_string(data, first, last) end
    if token == "[" then
      local indexed = last - first > 1
      next_token()
      return parse_list_or_array(indexed)
    end
    if token == "{" then
      next_token()
      return parse_map()
    end
    if token == "(" then
      next_token()
      return parse_scope()
    end
    return syntax_error(tibs, first, filename)
  end

  next_token()
  return parse_value()
end

return Tibs
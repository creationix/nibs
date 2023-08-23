local ffi = require 'ffi'
local typeof = ffi.typeof
local cast = ffi.cast

local U8Ptr = typeof "uint8_t*"
local U8Arr = typeof "uint8_t[?]"

local bit = require 'bit'
local rshift = bit.rshift
local lshift = bit.lshift
local bor = bit.bor


local p = require('deps/pretty-print').prettyPrint

---@class Nibs
local Nibs = {}

---@class Tibs
local Tibs = {}
Nibs.Tibs = Tibs

---@alias LexerSymbols "{"|"}"|"["|"]"|":"|","|"("|")
---@alias LexerToken "string"|"number"|"bytes"|"true"|"false"|"null"|"nan"|"inf"|"-inf"|"ref"|"error"|LexerSymbols

---@param data integer[]
---@param len integer
---@return fun():LexerToken?,integer?,integer?
local function tokenize(data, len)
  local char = string.char
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
      elseif c == 0x7c then -- "|"
        local start = offset
        offset = offset + 1
        while offset < len do
          c = data[offset]
          if c == 0x09 or c == 0x20 then -- "\t" | " "
            offset = offset + 1
            -- Skip horizontal whitespace
          elseif (c >= 0x30 and c <= 0x39)
              or (c >= 0x41 and c <= 0x41)
              or (c >= 0x61 and c <= 0x66) then
            -- hex digit
            offset = offset + 1
          elseif c == 0x7c then -- "|"
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

function Tibs.format_syntax_error(tibs, error_offset, filename)
  local index = error_offset + 1
  local c = string.sub(tibs, index, index)
  if c then
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
    return string.format("Tibs syntax error: Unexpected %q (%s:%d:%d)", c, filename or "[input string]", row, col)
  end
  return "Lexer error: Unexpected EOS"
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

---@alias Tibs.Bytes integer[] cdata uint8_t[?]
---@alias Tibs.Value Tibs.List|Tibs.Map|Tibs.Array|Tibs.Bytes|number|integer|string|boolean|nil

local colorize = require('deps/pretty-print').colorize

---@param c integer
---@return boolean
local function is_hex_char(c)
  return (c <= 0x39 and c >= 0x30)
      or (c <= 0x66 and c >= 0x61)
      or (c >= 0x41 and c <= 0x46)
end

---@param c integer
---@return integer
local function from_hex_char(c)
  return c <= 0x39 and c - 0x30
      or c >= 0x61 and c - 0x57
      or c - 0x37
end

---@param tibs string
---@param filename? string
---@return any? value
---@return string? error
function Tibs.parse(tibs, filename)
  local data = cast(U8Ptr, tibs)
  local len = #tibs
  local _next_token = tokenize(data, len)

  local utoken, ufirst, ulast
  local function next_token()
    local token, first, last
    if utoken then
      token, first, last, utoken, ufirst, ulast = utoken, ufirst, ulast, nil, nil, nil
    else
      token, first, last = _next_token()
      print(string.format("% 10s % 10d % 10d %s",
        token, first, last,
        colorize("highlight", string.sub(tibs, first + 1, last))
      ))
    end
    return token, first, last
  end
  local function peek_token()
    local token, first, last = next_token()
    utoken, ufirst, ulast = token, first, last
    return token
  end

  local function syntax_error(first)
    -- print(debug.traceback("", 2))
    return nil, Tibs.format_syntax_error(tibs, first, filename)
  end

  local parse_value

  ---@param token? LexerToken
  ---@param first? integer
  ---@param last? integer
  ---@return Map|nil array
  ---@return nil|string error
  local function parse_object(token, first, last)
    print("parse Object start")
    local obj = setmetatable({}, MapMeta)
    while token ~= "}" do
      -- Parse key
      local key, value, err
      p { key_token = token }
      key, err = parse_value(token, first, last)
      if err then return nil, err end
      if key == nil then return syntax_error(first) end

      -- Parse colon
      token, first = next_token()
      p { colon_token = token }
      if token ~= ":" then return syntax_error(first) end

      -- Parse value
      token, first, last = next_token()
      value, err = parse_value(token, first, last)
      if err then return nil, err end
      rawset(obj, key, value)

      -- Parse comma or end
      token, first = next_token()
      if token == "}" then break end
      if token == "," then
        token, first, last = next_token()
      else
        return syntax_error(first)
      end
    end
    print("parse Object end")
    return obj
  end

  ---@param indexed? true
  ---@param token? LexerToken
  ---@param first? integer
  ---@param last? integer
  ---@return List|Array|nil array
  ---@return nil|string error
  local function parse_array(indexed, token, first, last)
    print "Parse Array Start"
    local arr = setmetatable({}, indexed and ArrayMeta or ListMeta)
    local length = 0
    while token ~= "]" do
      local value, err = parse_value(token, first, last)
      if err then return nil, err end
      length = length + 1
      rawset(arr, length, value)
      token, first = next_token()
      if token == "]" then break end
      if token == "," then
        token, first, last = next_token()
      else
        return syntax_error(first)
      end
    end
    print "Parse Array End"
    return arr
  end

  ---@param first integer
  ---@param last integer
  ---@return nil
  ---@return string
  local function parse_scope(token, first, last)
    local scope = setmetatable({}, ScopeMeta)
    local length = 0
    while token ~= ")" do
      local value, err = parse_value(token, first, last)
      if err then return nil, err end
      length = length + 1
      rawset(scope, length, value)
      token, first = next_token()
      if token == ")" then break end
      if token == "," then
        token, first, last = next_token()
      end
    end
    return scope
  end

  local function parse_string(first, last)
    -- TODO: handle escaped strings
    return tibs:sub(first + 2, last - 1)
  end

  local function parse_number(first, last)
    -- TODO: handle big integers
    return tonumber(tibs:sub(first + 1, last))
  end

  local function parse_bytes(first, last)
    local slices = { first, last }
    while peek_token() == "bytes" do
      local _
      _, first, last = next_token()
      slices[#slices + 1] = first
      slices[#slices + 1] = last
    end
    local total_nibbles = 0
    for i = 1, #slices, 2 do
      local line_first = slices[i] + 1
      local line_last = slices[i + 1] - 1
      local j = line_first
      while j <= line_last do
        local c = data[j]
        j = j + 1
        if is_hex_char(c) then
          total_nibbles = total_nibbles + 1
          c = data[j]
          j = j + 1
          if is_hex_char(c) then
            total_nibbles = total_nibbles + 1
          else
            return syntax_error(j)
          end
        end
      end
    end
    if total_nibbles % 2 > 0 then
      return syntax_error(first)
    end
    local size = rshift(total_nibbles, 1)

    p(slices, total_nibbles)

    local buf = U8Arr(size)
    local offset = 0
    for i = 1, #slices, 2 do
      local line_first = slices[i] + 1
      local line_last = slices[i + 1] - 1
      local j = line_first
      while j <= line_last do
        local c = data[j]
        j = j + 1
        if is_hex_char(c) then
          local high = lshift(from_hex_char(c), 4)
          c = data[j]
          j = j + 1
          buf[offset] = bor(high, from_hex_char(c))
          offset = offset + 1
        end
      end
    end
    p(ffi.string(buf, size))
    return buf
  end

  ---@param first integer
  ---@param last integer
  ---@return Tibs.Ref? ref
  ---@return string? error
  local function parse_ref(first, last)
    local id, err = parse_number(first + 1, last)
    if err then return nil, err end
    return (setmetatable({ id }, RefMeta))
  end


  ---@param token? LexerToken
  ---@param first? integer
  ---@param last? integer
  ---@return Value parsed_value
  ---@return nil|string syntax_error
  function parse_value(token, first, last)
    if token == "{" then return parse_object(next_token()) end
    if token == "[" then return parse_array(last - first > 1, next_token()) end
    if token == "(" then return parse_scope(next_token()) end
    if token == "string" then return parse_string(first, last) end
    if token == "number" then return parse_number(first, last) end
    if token == "bytes" then return parse_bytes(first, last) end
    if token == "true" then return true end
    if token == "false" then return false end
    if token == "null" then return nil end
    if token == "nan" then return 0 / 0 end
    if token == "inf" then return 1 / 0 end
    if token == "-inf" then return -1 / 0 end
    if token == "ref" then return parse_ref(first, last) end
    return nil, Tibs.format_syntax_error(tibs, first, filename)
  end

  return parse_value(next_token())
end

return Nibs

---@class Nibs
local Nibs = {}


---@class Nibs.Tibs
local Tibs = {}
Nibs.Tibs = Tibs

---@alias LexerToken "error"|"string"|"bytes"|"number"|"true"|"false"|"null"|"nan"|"inf"|"-inf"|"ref"|":"|","|"{"|"}"|"["|"]"|"("|")"

---@param tibs string
---@return fun():LexerToken|nil, integer|nil, integer|nil
function Tibs.lexer(tibs)
  local ffi = require 'ffi'
  local data = ffi.cast("uint8_t*", tibs)
  local char = string.char
  local first = 0
  local last = #tibs

  -- Consume a sequence of zero or more digits [0-9]
  local function consume_digits()
    while first < last do
      local c = data[first]
      if c < 0x30 or c > 0x39 then break end -- outside "0-9"
      first = first + 1
    end
  end

  -- Consume a single optional character
  ---@param c1 integer
  ---@param c2? integer
  ---@return boolean did_match
  local function consume_optional(c1, c2)
    if first < last then
      local c = data[first]
      if c == c1 or c == c2 then
        first = first + 1
        return true
      end
    end
    return false
  end

  ---@return LexerToken|nil token
  ---@return integer|nil first
  ---@return integer|string|nil last or error
  return function()
    while first < last do
      local c = data[first]
      if c == 0x0d or c == 0x0a or c == 0x09 or c == 0x20 then
        -- "\r" | "\n" | "\t" | " "
        -- Skip whitespace
        first = first + 1
      elseif c == 0x2f and first < last and data[first] == 0x2f then
        -- '//'
        -- Skip comments
        first = first + 2
        while first < last do
          c = data[first]
          first = first + 1
          if c == 0x0d or c == 0x0a then -- "\r" | "\n"
            break
          end
        end
      elseif c == 0x5b or c == 0x5d or c == 0x7b or c == 0x7d or c == 0x3a or c == 0x2c or c == 0x28 or c == 0x29 then
        -- "[" | "]" "{" | "}" | ":" | "," | "(" | ")"
        -- Pass punctuation through as-is
        local start = first
        first = first + 1
        if c == 0x5b and first < last and data[first] == 0x23 then -- "#"
          first = first + 1
        end
        return char(c), start, first
      elseif c == 0x22 then -- double quote
        -- Parse Strings
        local start = first
        first = first + 1
        while first < last do
          c = data[first]
          if c == 0x22 then -- double quote
            first = first + 1
            return "string", start, first
          elseif c == 0x5c then              -- backslash
            first = first + 2
          elseif c == 0x0d or c == 0x0a then -- "\r" | "\n"
            -- newline is not allowed
            break
          else -- other characters
            first = first + 1
          end
        end
        return "error", first, first
      elseif c == 0x2d                      -- "-"
          or (c >= 0x30 and c <= 0x39) then -- "0"-"9"
        local start = first
        first = first + 1
        consume_digits()
        if consume_optional(0x2e) then -- "."
          consume_digits()
        end
        if consume_optional(0x45, 0x65) then -- "e"|"E"
          consume_optional(0x2b, 0x2d)       -- "+"|"-"
          consume_digits()
        end
        return "number", start, first
      elseif c == 0x7c then -- "|"
        local start = first
        first = first + 1
        while first < last do
          c = data[first]
            first = first + 1
          if c == 0x09 or c == 0x20 then
            -- "\t" | " "
            -- Skip horizontal whitespace
          elseif (c >= 0x30 and c <= 0x39)
              or (c >= 0x41 and c <= 0x41)
              or (c >= 0x61 and c <= 0x66) then
            -- hex digit
            first = first + 1
          elseif c == 0x7c then -- "|"
            first = first + 1
            return "bytes", start, first
          else
            break
          end
        end
        return "error", first, first
      elseif c == 0x26 then -- "&" then
        -- parse refs
        local start = first
        first = first + 1
        if first > last then return "error", first, first end
        consume_digits()
        return "ref", start, first
      elseif c == 0x74 and first + 3 < last     -- "t"
          and data[first + 1] == 0x72      -- "r"
          and data[first + 2] == 0x75      -- "u"
          and data[first + 3] == 0x65 then -- "e"
        first = first + 4
        return "true", first - 4, first
      elseif c == 0x66 and first + 4 < last     -- "f"
          and data[first + 1] == 0x61      -- "a"
          and data[first + 2] == 0x6c      -- "l"
          and data[first + 3] == 0x73      -- "s"
          and data[first + 4] == 0x65 then -- "e"
        first = first + 5
        return "false", first - 5, first
      elseif c == 0x6e and first + 3 < last     -- "n"
          and data[first + 1] == 0x75      -- "u"
          and data[first + 2] == 0x6c      -- "l"
          and data[first + 3] == 0x6c then -- "l"
        first = first + 4
        return "null", first - 4, first
      elseif c == 0x6e and first + 2 < last     -- "n"
          and data[first + 1] == 0x61      -- "a"
          and data[first + 2] == 0x6e then -- "n"
        first = first + 3
        return "nan", first - 3, first
      elseif c == 0x69 and first + 2 < last     -- "i"
          and data[first + 1] == 0x6e      -- "n"
          and data[first + 2] == 0x66 then -- "f"
        first = first + 3
        return "inf", first - 3, first
      elseif c == 0x2d and first + 3 < last     -- "-"
          and data[first + 1] == 0x69      -- "i"
          and data[first + 2] == 0x6e      -- "n"
          and data[first + 3] == 0x66 then -- "f"
        first = first + 4
        return "-inf", first - 4, first
      else
        return "error", first, first
      end
    end
  end
end

function Tibs.format_syntax_error(tibs, index, filename)
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


return Nibs

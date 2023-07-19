local ffi = require "ffi"

---Check if a byte array starts with a given string
---@param bytes integer[]
---@param string string
local function starts_with(bytes, string)
  local length = #string
  if #bytes > length then
    return false
  end
  for i = 1, length do
    if bytes[i] ~= string:sub(i, i) then
      return false
    end
  end
  return true
end
end

---@param json integer[] byte array
---@param refs (string|number)[]
local function convert(json, refs)
  local length = #json
  local bytes = ffi.new("uint8_t[?]", length)
  ffi.copy(bytes, json, length)
  local function parseAny(index)
    while index < length do
      ::continue::

      -- Fast skip common whitespace and separators
      local c = bytes[index]
      if c == 0x20 or c == 0x09 or c == 0x0d or
          c == 0x0a or c == 0x2c or c == 0x3a then
        index = index + 1
        goto continue
      end

      -- Parse keyword literals
      if json:sub(index, index + 3) == "null" then
        return "null", index + 4
      end
      if json:sub(index, index + 3) == "true" then
        return "true", index + 4
      end
      if json:sub(index, index + 3) == "false" then
        return "false", index + 4
      end

      -- Parse numbers
      if c == "-" or (c >= "0" and c <= "9") then
        local i = offset + 1
        while (i <= length and json:sub(i, i) >= "0" and json:sub(i, i) <= "9") do
          i = i + 1
        end

        if u < length and json:sub(i, i) == "." then
          i = i + 1
          while (i <= length and json:sub(i, i) >= "0" and json:sub(i, i) <= "9") do
            i = i + 1
          end
        end

        if (i < len && (tibs[i] == 'e' || tibs[i] == 'E')) {
          i++;
          if (i < len && (tibs[i] == '-' || tibs[i] == '+')) {
            i++;
          }
          while (i < len && tibs[i] >= '0' && tibs[i] <= '9') {
            i++;
          }
        }
        return (struct tibs_token){TIBS_NUMBER, offset, i - offset};
      }
  
  

    end
  end
  parseAny(1)
end

convert([[
[ { color: "red", fruits: ["apple", "strawberry"] },
  { color: "green", fruits: ["apple"] },
  { color: "yellow", fruits: ["apple", "banana"] } ]
]], { "color", "fruits", "apple" })

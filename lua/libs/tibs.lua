local NibLib = require 'nib-lib'

local bit = require 'bit'
local bor = bit.bor
local band = bit.band
local rshift = bit.rshift

local I64 = NibLib.I64

local byte = string.byte
local char = string.char
local sub = string.sub
local format = string.format

local floor = math.floor
local concat = table.concat

--- Tibs is a texual representation of the Nibs datamodel.
--- It's a superset of JSON so that any data that matches JSON's model
--- will have the same syntax.  Also it means that any JSON document can
--- be parsed as Tibs for easy importing of legacy data.
local Tibs = {}

--- Ordered list of values (same as JSON Array)
---@class List
local List = { __name = "List", __is_array_like = true }
Tibs.List = List
do
    -- Weak keys for storing array length out of table
    local lengths = setmetatable({}, { __mode = "k" })
    local function getLength(self)
        local length = lengths[self]
        if not length then
            local l = 0
            repeat
                l = l + 1
            until rawget(self, l) == nil
            length = l - 1
            lengths[self] = length
        end
        return length
    end

    function List.new(...)
        local self = setmetatable({}, List)
        local count = select("#", ...)
        if count > 0 then
            local input = { ... }
            for i = 1, count do
                self[i] = input[i]
            end
        end
        return self
    end

    function List.fromTable(list)
        local self = setmetatable(list, List)
        lengths[self] = #list
        return self
    end

    function List:__newindex(key, value)
        local length = getLength(self)

        if type(key) == "number" and floor(key) == key then
            if key > length then
                lengths[self] = key
            end
        end
        rawset(self, key, value)
    end

    function List:__len()
        return getLength(self)
    end

    function List:__ipairs()
        local length = getLength(self)
        return coroutine.wrap(function()
            for i = 1, length do
                coroutine.yield(i, rawget(self, i))
            end
        end)
    end

    function List.setLength(self, length)
        local oldLength = getLength(self)
        -- Trim away lua values that are now outside the array range
        if length < oldLength then
            for i = oldLength, length + 1, -1 do
                rawset(self, i, nil)
            end
        end
        -- Update the length metadata
        lengths[self] = length
    end
end

--- Ordered mapping from a value to any value (superset of JSON Object)
---@class Map
local Map = { __name = "Map", __is_array_like = false }
Tibs.Map = Map
do
    -- Weak keys for storing object order out of table
    local orders = setmetatable({}, { __mode = "k" })
    local function getOrder(self)
        local order = orders[self]
        if not order then
            order = {}
            local k
            repeat
                k = next(self, k)
                if k then
                    table.insert(order, k)
                end
            until not k
            orders[self] = order
        end
        return order
    end

    function Map:__pairs()
        local order = getOrder(self)
        return coroutine.wrap(function()
            for i = 1, #order do
                local k = order[i]
                coroutine.yield(k, rawget(self, k))
            end
        end)
    end

    function Map.__len() return 0 end

    function Map:__newindex(key, value)
        local order = getOrder(self)
        local found = false
        for i = 1, #order do
            if order[i] == key then
                found = true
                break
            end
        end
        if not found then
            table.insert(order, key)
        end
        return rawset(self, key, value)
    end

    ---Given a list of alternative keys and pairs as arguments, return an ordered object.
    --- For example, an empty object is `Object.new()`
    --- But one with multiple pairs is `Object.new(k1, v1, k2, v2, ...)`
    ---@return Map
    function Map.new(...)
        local self = setmetatable({}, Map)
        local count = select("#", ...)
        if count > 0 then
            local input = { ... }
            for i = 1, count, 2 do
                self[input[i]] = input[i + 1]
            end
        end
        return self
    end

    ---Create a Map instance from any lua table.
    ---@param tab table
    ---@return Map
    function Map.fromTable(tab)
        local self = setmetatable({}, Map)
        for k, v in pairs(tab) do
            self[k] = v
        end
        return self
    end

    --- Since we have JavaScript style semantics, setting to nil doesn't delete
    --- This function actually deletes a value.
    function Map.delete(self, key)
        local order = getOrder(self)
        local skip = false
        for i = 1, #order + 1 do
            if skip then
                order[i - 1] = order[i]
                order[i] = nil
            elseif order[i] == key then
                skip = true
            end
        end
        rawset(self, key, nil)
    end
end


--- Same as List, but marked for indexing when serializing to nibs
---@class Array
local Array = { __name = "Array", __is_array_like = true, __is_indexed = true }
Tibs.Array = Array
do
    ---Create an Array instance from many arguments (including nils)
    ---@return Array
    function Array.new(...)
        return setmetatable(List.new(...), Array)
    end

    ---Create an Array instance from a lua table
    ---@param table table
    ---@return Array
    function Array.fromTable(table)
        return setmetatable(List.fromTable(table), Array)
    end

    Array.__len = List.__len
    Array.__newindex = List.__newindex
    Array.__ipairs = List.__ipairs
end

--- Same as Map, but marked for indexing when serializing to nibs
---@class Trie
local Trie = { __name = "Trie", __is_array_like = false, __is_indexed = true }
Tibs.Trie = Trie
do
    function Trie.new(...)
        return setmetatable(Map.new(...), Trie)
    end

    Trie.__len = Map.__len
    Trie.__newindex = Map.__newindex
    Trie.__pairs = Map.__pairs
end

--- Class used to store references when encoding.
---@class Ref
---@field index number
local Ref = { __name = "Ref" }
Tibs.Ref = Ref
do
    ---Construct a nibs ref instance from a ref index
    ---@param index number
    ---@return Ref
    function Ref.new(index)
        return setmetatable({ index }, Ref)
    end

    function Ref:__tojson()
        return '&' .. self[1]
    end
end

--- Scope used to encode references.
---@class Scope
local Scope = { __name = "Scope", __is_array_like = true, __is_indexed = true }
Tibs.Scope = Scope
do

    ---Construct a nibs ref scope from a list of values to be referenced and a child value
    ---@param list Value[] list of values that can be referenced with value as last
    function Scope.new(list)
        return setmetatable(List.fromTable(list), Scope)
    end

    function Scope:__tojson(inner)
        local parts = {}
        for i, v in ipairs(self) do
            parts[i] = inner(v)
        end
        return '(' .. concat(parts, ',') .. ')'
    end

    Scope.__len = List.__len
    Scope.__newindex = List.__newindex
    Scope.__ipairs = List.__ipairs

end

-- Unique token used for parse errors
local Fail = { FAIL = true }
Tibs.Fail = Fail

-- Wrap parser implementation in collapsable block scope
-- Tibs.decode(json)
do

    -- Hoist declarations
    local nextToken, parseAny,
    parseNumber, parseRef, parseString, parseBytes,
    parseArray, parseObject, parseScope

    --- This is the main public interface.  Given a json string return
    --- the lua representation.  Array/Object/null semantics are preserved.
    ---@param json string
    ---@return boolean|string|number|table|nil parsed value
    ---@return string? error
    function Tibs.decode(json)
        assert(type(json) == "string", "JSON or Tibs string expected")
        local value, index = parseAny(json, 1)
        local b

        -- Make sure there is only whitespace after value,
        -- otherwise fail the parse.
        if value ~= Fail then
            b, index = nextToken(json, index)
            if b then value = Fail end
        end

        -- Return the value if it's still value.
        if value ~= Fail then
            return value
        end

        local row = 0
        local col = 0
        for line in string.gmatch(string.sub(json, 1, index - 1), "[^\r\n]*\r?\n?") do
            if #line > 0 then
                row = row + 1
                col = #line + 1
            end
        end

        -- Report parse error
        if index <= #json then
            return nil, format("Unexpected %q at index %d (row %d / col %d)",
                sub(json, index, index), index, row, col)
        end
        return nil, format("Unexpected EOS at index %d (row %d / col %d)", index, row, col)
    end

    ---Skip whitespace and get next byte
    ---@param json string
    ---@param index number
    ---@return number next_byte
    ---@return number new_index
    function nextToken(json, index)
        while true do
            local b = byte(json, index)
            if not (b == 9 or b == 10 or b == 13 or b == 32) then
                return b, index
            end
            index = index + 1
        end
    end

    function parseNumber(json, index)
        local b, start = nextToken(json, index)

        -- Optional leading `-`
        if b == 45 then -- `-`
            index = index + 1
            b = byte(json, index, index)
        end

        -- Integer part of number
        if b == 48 then -- `0`
            index = index + 1
            b = byte(json, index)
        elseif b and (b >= 49 and b <= 57) then -- `[1-9]`
            index = index + 1
            b = byte(json, index)
            while b and (b >= 48 and b <= 57) do -- `[0-9]*`
                index = index + 1
                b = byte(json, index)
            end
        else
            -- Must be zero or positive integer
            return Fail, index
        end

        -- optional decimal part of number
        if b == 46 then -- `.`
            index = index + 1
            b = byte(json, index)

            -- Can't stop here, must have at least one `[0-9]`.
            if not b or b < 48 or b > 57 then
                return Fail, index
            end

            while b and (b >= 48 and b <= 57) do -- `0-9`
                index = index + 1
                b = byte(json, index)
            end
        end

        -- Optional exponent part of number
        if b == 69 or b == 101 then -- `E` or `e`
            index = index + 1
            b = byte(json, index)

            -- Optional sign inside exponent
            if b == 43 or b == 45 then -- `+` or `-`
                index = index + 1
                b = byte(json, index)
            end

            -- Can't stop here, must have at least one `[0-9]`.
            if not b or b < 48 or b > 57 then
                return Fail, index
            end
            while b and (b >= 48 and b <= 57) do -- `0-9`
                index = index + 1
                b = byte(json, index)
            end
        end

        local text = sub(json, start, index - 1)
        local num
        if string.match(text, "^-?[0-9]+$") then
            local sign = I64(-1)
            local big = I64(0)
            for i = 1, #text do
                if string.sub(text, i, i) == "-" then
                    sign = I64(1)
                else
                    big = big * 10LL - I64(byte(text, i) - 48)
                end
            end

            num = NibLib.tonumberMaybe(big *sign)
        else
            num = tonumber(text,10)
        end

        return num, index
    end

    local stringEscapes = {
        [92] = char(92),
        [34] = char(34),
        [47] = char(47),
        [98] = char(8),
        [102] = char(12),
        [110] = char(10),
        [114] = char(13),
        [116] = char(9),
    }

    local highPair = nil
    local function utf8Encode(c)
        -- Encode surrogate pairs as a single utf8 codepoint
        if highPair then
            local lowPair = c
            c = ((highPair - 0xd800) * 0x400) + (lowPair - 0xdc00) + 0x10000
        elseif c >= 0xd800 and c <= 0xdfff then --surrogate pair
            highPair = c
            return nil, true
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

    local function parseEscapedString(json, index)
        local b = byte(json, index)
        if b ~= 34 then -- `"`
            return Fail, index
        end
        index = index + 1
        b = byte(json, index)

        local first = index
        local parts = {}
        local i = 1
        local pairHalf
        while b ~= 34 do -- `"`
            if not b then return Fail, index end
            if b == 92 then -- `\`
                if index > first then
                    parts[i] = sub(json, first, index - 1)
                    i = i + 1
                end
                index = index + 1
                b = byte(json, index)
                if not b then return Fail, index end

                local e = stringEscapes[b]
                if e then
                    parts[i] = e
                    i = i + 1
                    index = index + 1
                    b = byte(json, index)
                    first = index
                elseif b == 117 then -- `u`
                    local d = 0
                    -- 4 required digits
                    for _ = 1, 4 do
                        index = index + 1
                        b = byte(json, index)
                        if not b then
                            return Fail, index
                        end
                        if b >= 48 and b <= 57 then
                            d = (d * 16) + (b - 48)
                        elseif b >= 97 and b <= 102 then
                            d = (d * 16) + (b - 87)
                        elseif b >= 65 and b <= 70 then
                            d = (d * 16) + (b - 55)
                        else
                            return Fail, index
                        end
                    end
                    local encoded
                    encoded, pairHalf = utf8Encode(d)
                    if encoded then
                        parts[i] = encoded
                        i = i + 1
                    end
                    index = index + 1
                    b = byte(json, index)
                    first = index
                end
            else
                index = index + 1
                b = byte(json, index)
            end
        end
        if index > first then
            parts[i] = sub(json, first, index - 1)
            i = i + 1
        end
        if pairHalf then
            parts[i] = "?"
        end
        return concat(parts), index + 1
    end

    function parseString(json, index)
        local b, start = nextToken(json, index)
        index = start
        if b ~= 34 then -- `"`
            return Fail, index
        end
        index = index + 1
        b = byte(json, index)

        while b ~= 34 do -- `"`
            if not b then return Fail, index end
            if b == 92 then -- `\`
                return parseEscapedString(json, start)
            else
                index = index + 1
                b = byte(json, index)
            end
        end
        return sub(json, start + 1, index - 1), index + 1
    end

    function parseBytes(json, index)
        local b
        b, index = nextToken(json, index)
        if b ~= 60 then -- `<`
            return Fail, index
        end
        index = index + 1
        local start = index

        b, index = nextToken(json, index)

        while b ~= 62 do -- `>`
            if not b
                or (b < 48 or b > 57) -- `0`-`9`
                and (b < 65 or b > 70) -- `A`-`F`
                and (b < 97 or b > 102) -- `a`-`f`
            then
                return Fail, index
            end
            index = index + 1
            b, index = nextToken(json, index)
        end
        local inner = sub(json, start, index - 1)
        local bytes = NibLib.hexStrToBuf(inner:gsub('[ \n\r\t]+', ''))
        return bytes, index + 1
    end

    function parseArray(json, index)
        local b
        -- Consume opening square bracket
        b, index = nextToken(json, index)
        if b ~= 91 then return Fail, index end -- `[`
        index = index + 1

        -- Consume indexed tag
        local indexed = false
        b, index = nextToken(json, index)
        if b == 35 then -- `#`
            indexed = true
            index = index + 1
        end

        local array = indexed and Tibs.Array.new() or Tibs.List.new()
        local i = 1
        while true do
            -- Read the next token
            b, index = nextToken(json, index)
            if not b then return Fail, index end

            -- Exit the loop if it's a closing square bracket
            if b == 93 then -- `]`
                index = index + 1
                break
            end

            -- Consume a comma if we're not on the first loop
            if i > 1 then
                if b ~= 44 then return Fail, index end -- `,`
                index = index + 1
            end

            b, index = nextToken(json, index)
            if not b then return Fail, index end

            -- Allow trailing commas by checking agin for closing brace
            if b == 93 then -- `]`
                index = index + 1
                break
            end


            -- Parse a single value and add to the array
            local value
            value, index = parseAny(json, index)
            if value == Fail then
                return Fail, index
            end
            array[i] = value
            i = i + 1
        end
        return array, index
    end

    function parseObject(json, index)
        local b
        -- Consume opening curly brace
        b, index = nextToken(json, index)
        if b ~= 123 then return Fail, index end -- `{`
        index = index + 1

        -- Consume indexed tag
        local indexed = false
        b, index = nextToken(json, index)
        if b == 35 then -- `#`
            indexed = true
            index = index + 1
        end

        local object = indexed and Tibs.Trie.new() or Tibs.Map.new()
        local i = 1
        while true do
            -- Read the next token
            b, index = nextToken(json, index)
            if not b then return Fail, index end

            -- Exit the loop if it's a closing curly brace
            if b == 125 then -- `}`
                index = index + 1
                break
            end

            -- Consume a comma if we're not on the first loop
            if i > 1 then
                if b ~= 44 then return Fail, index end -- `,`
                index = index + 1
            end

            b, index = nextToken(json, index)
            if not b then return Fail, index end

            -- Allow trailing commas by checking again for closing brace
            if b == 125 then -- `}`
                index = index + 1
                break
            end

            -- Parse a single value as key
            local key
            key, index = parseAny(json, index)
            if key == Fail then
                return Fail, index
            end

            -- Consume the colon
            b, index = nextToken(json, index)
            if b ~= 58 then return Fail, index end -- `:`
            index = index + 1

            -- Parse a single value
            local value
            value, index = parseAny(json, index)
            if value == Fail then
                return Fail, index
            end

            -- Add the key/value pair to the object
            object[key] = value
            i = i + 1
        end
        return object, index
    end

    function parseScope(json, index)
        local b
        -- Consume opening paren brace
        b, index = nextToken(json, index)
        if b ~= 40 then return Fail, index end -- `(`
        index = index + 1

        -- Parse a single value as child
        local child
        child, index = parseAny(json, index)
        if child == Fail then
            return Fail, index
        end

        local scope = Tibs.List.new(child)
        local i = 1
        while true do
            -- Read the next token
            b, index = nextToken(json, index)
            if not b then return Fail, index end

            -- Exit the loop if it's a closing paren
            if b == 41 then -- `)`
                index = index + 1
                break
            end

            -- Consume a comma
            if b ~= 44 then return Fail, index end -- `,`
            index = index + 1

            local ref
            ref, index = parseAny(json, index)
            if ref == Fail then
                return Fail, index
            end
            i = i + 1
            scope[i] = ref

        end
        return Tibs.Scope.new(scope), index
    end

    function parseRef(json, index)
        local b
        -- Consume ampersand
        b, index = nextToken(json, index)
        if b ~= 38 then return Fail, index end -- `&`
        index = index + 1

        local idx
        idx, index = parseNumber(json, index)
        if not idx then return nil, index end
        return Tibs.Ref.new(idx), index
    end

    function parseAny(json, index)
        -- Exit if we run out of string to parse
        local b
        b, index = nextToken(json, index)
        if not b then return Fail, index end

        -- Parse based on first character
        if b == 123 then -- `{` `}`
            return parseObject(json, index)
        elseif b == 91 then -- `[` `]`
            return parseArray(json, index)
        elseif b == 40 then -- `(` `)`
            return parseScope(json, index)
        elseif b == 38 then -- `&`
            return parseRef(json, index)
        elseif b == 34 then -- `"`
            return parseString(json, index)
        elseif b == 60 then -- `<`
            return parseBytes(json, index)
        elseif b == 45 and sub(json, index, index + 3) == "-inf" then
            return -1 / 0, index + 4
        elseif b == 110 and sub(json, index, index + 2) == "nan" then
            return 0 / 0, index + 3
        elseif b == 105 and sub(json, index, index + 2) == "inf" then
            return 1 / 0, index + 3
        elseif b == 45 or (b >= 48 and b <= 57) then -- `-` or `0-9`
            return parseNumber(json, index)
        elseif b == 102 and sub(json, index, index + 4) == "false" then
            return false, index + 5
        elseif b == 116 and sub(json, index, index + 3) == "true" then
            return true, index + 4
        elseif b == 110 and sub(json, index, index + 3) == "null" then
            return nil, index + 4
        else
            return Fail, index
        end
    end

end

-- Wrap encoder implementation in collapsable block scope
-- Tibs.encode(val)
do
    local encode

    local stringEscapes = {
        [92] = 92, -- `\\`
        [34] = 34, -- `\"`
        [8] = 98, -- `\b`
        [12] = 102, -- `\f`
        [10] = 110, -- `\n`
        [13] = 114, -- `\r`
        [9] = 116, --`\t`
    }

    ---@param num number|ffi.cdata*
    ---@return string
    local function encodeNumber(num)
        if NibLib.isWhole(num) then
            return (tostring(I64(num)):gsub("[IUL]+", ""))
        else
            return tostring(num)
        end
    end

    local function encodeString(str)
        local start = 1
        local parts = {}
        local i = 1
        local len = #str
        for index = start, len do
            local escape = stringEscapes[byte(str, index)]
            if escape then
                if index > start then
                    parts[i] = sub(str, start, index - 1)
                    i = i + 1
                end
                parts[i] = char(92, escape)
                i = i + 1
                start = index + 1
            end
        end
        if len >= start then
            parts[i] = sub(str, start, len)
        end
        return '"' .. concat(parts) .. '"'
    end

    local function encodeArray(arr, tag)
        local parts = {}
        for i, v in ipairs(arr) do
            parts[i] = encode(v)
        end
        return "[" .. tag .. concat(parts, ",") .. "]"
    end

    local function encodeObject(obj, tag)
        local parts = {}
        local i = 1
        for k, v in pairs(obj) do
            parts[i] = encode(k) .. ':' .. encode(v)
            i = i + 1
        end
        return "{" .. tag .. concat(parts, ",") .. "}"
    end

    local reentered = nil
    function Tibs.encode(val)

        local typ = type(val)
        if typ == 'nil' then
            return "null"
        elseif typ == 'boolean' then
            return val and 'true' or 'false'
        elseif typ == 'string' then
            return encodeString(val)
        elseif typ == 'number' then
            return encodeNumber(val)
        elseif typ == 'table' then

            local mt = getmetatable(val)
            if mt and reentered ~= val and mt.__tojson then
                reentered = val
                local json = mt.__tojson(val, Tibs.encode)
                reentered = nil
                return json
            end
            local tag = mt and mt.__is_indexed and "#" or ""
            if NibLib.isArrayLike(val) then
                return encodeArray(val, tag)
            else
                return encodeObject(val, tag)
            end
        elseif typ == 'cdata' then
            if NibLib.isInteger(val) or NibLib.isFloat(val) then
                -- Treat cdata integers and floats as numbers
                return encodeNumber(val)
            end
            local str = '<' .. NibLib.bufToHexStr(val) .. '>'
            return str
        else
            error("Cannot serialize " .. typ)
        end
    end

    encode = Tibs.encode
end

return Tibs

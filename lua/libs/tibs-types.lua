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

return Tibs

local floor = math.floor
local concat = table.concat

local Ordered = {}

--- JavaScript/JSON Object semantics for Lua tables
local OrderedMap = {}
Ordered.Map = OrderedMap
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

    OrderedMap.__name = "OrderedMap"
    OrderedMap.__is_array_like = false

    function OrderedMap:__pairs()
        local order = getOrder(self)
        return coroutine.wrap(function()
            for i = 1, #order do
                local k = order[i]
                coroutine.yield(k, rawget(self, k))
            end
        end)
    end

    function OrderedMap.__len() return 0 end

    function OrderedMap:__newindex(key, value)
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
    ---@return table
    function OrderedMap.new(...)
        local self = setmetatable({}, OrderedMap)
        local count = select("#", ...)
        if count > 0 then
            local input = { ... }
            for i = 1, count, 2 do
                self[input[i]] = input[i + 1]
            end
        end
        return self
    end

    --- Since we have JavaScript style semantics, setting to nil doesn't delete
    --- This function actually deletes a value.
    function OrderedMap.delete(self, key)
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

--- JavaScript/JSON Array semantics for Lua tables
local OrderedList = {}
Ordered.List = OrderedList
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

    OrderedList.__name = "OrderedList"
    OrderedList.__is_array_like = true

    function OrderedList.new(...)
        local self = setmetatable({}, OrderedList)
        local count = select("#", ...)
        if count > 0 then
            local input = { ... }
            for i = 1, count do
                self[i] = input[i]
            end
        end
        return self
    end

    function OrderedList.fromTable(list)
        local self = setmetatable(list, OrderedList)
        lengths[self] = #list
        return self
    end

    function OrderedList:__newindex(key, value)
        local length = getLength(self)

        if type(key) == "number" and floor(key) == key then
            if key > length then
                lengths[self] = key
            end
        end
        rawset(self, key, value)
    end

    function OrderedList:__len()
        return getLength(self)
    end

    function OrderedList:__ipairs()
        local length = getLength(self)
        return coroutine.wrap(function()
            for i = 1, length do
                coroutine.yield(i, rawget(self, i))
            end
        end)
    end

    function OrderedList.setLength(self, length)
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

-- Same as OrderedArray, but marked for indexing when serializing to nibs
local OrderedArray = {}
Ordered.Array = OrderedArray
do
    OrderedArray.__name = "OrderedArray"
    OrderedArray.__is_array_like = true
    OrderedArray.__is_indexed = true
    function OrderedArray.new(...)
        return setmetatable(OrderedList.new(...), OrderedArray)
    end

    OrderedArray.__len = OrderedList.__len
    OrderedArray.__index = OrderedList.__index
    OrderedArray.__newindex = OrderedList.__newindex
    OrderedArray.__pairs = OrderedList.__pairs
    OrderedArray.__ipairs = OrderedList.__ipairs
end

-- Same as OrderedMap, but marked for indexing when serializing to nibs
local OrderedTrie = {}
Ordered.Trie = OrderedTrie
do
    OrderedTrie.__name = "OrderedTrie"
    OrderedTrie.__is_indexed = true
    function OrderedTrie.new(...)
        return setmetatable(OrderedMap.new(...), OrderedTrie)
    end

    OrderedTrie.__len = OrderedMap.__len
    OrderedTrie.__index = OrderedMap.__index
    OrderedTrie.__newindex = OrderedMap.__newindex
    OrderedTrie.__pairs = OrderedMap.__pairs
    OrderedTrie.__ipairs = OrderedMap.__ipairs
end

function Ordered.__is_array_like(val)
    local mt = getmetatable(val)
    if mt and mt.__is_array_like ~= nil then
        return mt.__is_array_like
    end
    local i = 1
    for key in pairs(val) do
        if key ~= i then return false end
        i = i + 1
    end
    return true
end

--- Class used to store references when encoding.
---@class Ref
---@field index number
local Ref = {}
Ordered.Ref = Ref
do
    Ref.__name = "Ref"
    ---Construct a nibs ref instance from a ref index
    ---@return Ref
    function Ref.new(index)
        return setmetatable({ index }, Ref)
    end

    function Ref:__tojson()
        return '&' .. self[1]
    end
end

--- Scope used to encode references.
---@class RefScope
local RefScope = {}
Ordered.RefScope = RefScope
do
    RefScope.__name = "RefScope"

    ---Construct a nibs ref scope from a list of values to be referenced and a child value
    ---@param list Value[] list of values that can be referenced with value as last
    function RefScope.new(list)
        return setmetatable(OrderedList.fromTable(list), RefScope)
    end

    function RefScope:__tojson(inner)
        local parts = {}
        for i, v in ipairs(self) do
            parts[i] = inner(v)
        end
        return '(' .. concat(parts, ',') .. ')'
    end

    RefScope.__len = OrderedList.__len
    RefScope.__index = OrderedList.__index
    RefScope.__newindex = OrderedList.__newindex
    RefScope.__pairs = OrderedList.__pairs
    RefScope.__ipairs = OrderedList.__ipairs

end

return Ordered

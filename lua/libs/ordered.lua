local floor = math.floor

--- JavaScript/JSON Object semantics for Lua tables
local OrderedMap = {}
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

    OrderedMap.__name = "Map"

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

    OrderedList.__name = "List"

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

return {
    OrderedMap = OrderedMap,
    OrderedList = OrderedList,
}

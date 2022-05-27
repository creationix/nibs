--- JavaScript/JSON Object semantics for Lua tables
local OrderedTable = {}
-- Wrap Object implementation in collapsable block scope
do
    -- Weak keys for storing object order out of table
    local orders = setmetatable({}, { __mode = "k" })

    function OrderedTable:__pairs()
        local order = orders[self]
        return coroutine.wrap(function()
            for i = 1, #order do
                local k = order[i]
                coroutine.yield(k, rawget(self, k))
            end
        end)
    end

    function OrderedTable.__len() return 0 end

    function OrderedTable:__newindex(key, value)
        local order = orders[self]
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
    function OrderedTable.new(...)
        local self = setmetatable({}, OrderedTable)
        orders[self] = {}
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
    function OrderedTable.delete(self, key)
        local order = orders[self]
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


return OrderedTable

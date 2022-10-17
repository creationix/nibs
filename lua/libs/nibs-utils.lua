local Nibs = require 'nibs2'
local RefScope = Nibs.RefScope
local Reference = Nibs.Reference

local Ordered = require 'ordered'
local OrderedMap = Ordered.OrderedMap
local OrderedList = Ordered.OrderedList

local NibsUtils = {}

---Walk through a value and replace values found in the reference table with refs.
---@param value Value
---@param refs RefScope
function NibsUtils.addRefs(value, refs)
    ---@param o Value
    ---@return Value
    local function walk(o)
        if type(o) == "table" then
            if Nibs.is_array_like(o) then
                local a = OrderedList.new()
                for i, v in ipairs(o) do
                    a[i] = walk(v)
                end
                return a
            end
            local m = OrderedMap.new()
            for k, v in pairs(o) do
                m[walk(k)] = walk(v)
            end
            return m
        end
        for i, r in ipairs(refs) do
            if r == o then
                return Reference.new(i - 1)
            end
        end
        return o
    end

    return RefScope.new(walk(value), refs)
end

---Walk through a value and find duplicate values (sorted by frequency)
---@param value Value
---@retun Value[]
function NibsUtils.findDuplicateStrings(value)
    local seen = {}
    local duplicates = {}
    ---@param o Value
    ---@return Value
    local function walk(o)
        if type(o) == "table" then
            for k, v in pairs(o) do
                walk(k)
                walk(v)
            end
        elseif type(o) == "string" then
            local old = seen[o]
            if not old then
                seen[o] = 1
            else
                if old == 1 then
                    table.insert(duplicates, o)
                end
                seen[o] = old + 1
            end
        end
    end

    -- Extract all duplicate strings
    walk(value)
    -- Sort by frequency
    table.sort(duplicates, function(a, b)
        return seen[a] > seen[b] or seen[a] == seen[b] and a < b
    end)
    return duplicates
end

-- Find all repeated strings in a table recursively and sort by most frequent
function NibsUtils.findStrings(fn, limit, ...)
    local found = {}
    local seen = {}
    local function find(val)
        if type(val) == "table" then
            if seen[val] then return end
            seen[val] = true
            for k, v in pairs(val) do
                find(k)
                find(v)
            end
        elseif fn(val) then
            found[val] = (found[val] or 0) + 1
        end
    end

    local args = { ... }
    for i = 1, select("#", ...) do
        find(args[i])
    end

    local repeats = {}
    local keys = {}
    for k, v in pairs(found) do
        if v > limit then
            repeats[k] = v
            table.insert(keys, k)
        end
    end
    table.sort(keys, function(a, b)
        return repeats[a] > repeats[b]
    end)
    local result = OrderedMap.new()
    for _, k in ipairs(keys) do
        result[k] = repeats[k]
    end
    return result, keys
end

return NibsUtils

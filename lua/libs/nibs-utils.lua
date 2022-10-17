local Nibs = require 'nibs2'
local is_array_like = Nibs.is_array_like
local RefScope = Nibs.RefScope
local Reference = Nibs.Reference
local Array = Nibs.Array
local Trie = Nibs.Trie

local Ordered = require 'ordered'
local OrderedMap = Ordered.OrderedMap
local OrderedList = Ordered.OrderedList

local NibsUtils = {}

---Turn lists and maps into arrays and tries if they are over some limit
---@param value Value
---@param index_limit number
---@param seed number
---@param optimize number
function NibsUtils.enableIndices(value, index_limit, seed, optimize)
    index_limit = index_limit or 10
    seed = seed or 0
    optimize = optimize or 10

    ---@param o Value
    local function walk(o)
        if type(o) ~= "table" then return o end
        if is_array_like(o) then
            for i = 1, #o do
                o[i] = walk(o[i])
            end
            if #o < index_limit then return o end
            return Array.new(o)
        end
        local count = 0
        for k, v in pairs(o) do
            o[walk(k)] = walk(v)
            count = count + 1
        end
        if count < index_limit then return o end
        return Trie.new(o, seed, optimize)
    end

    return walk(value)
end

---Walk through a value and replace values found in the reference table with refs.
---@param value Value
---@param refs RefScope
function NibsUtils.addRefs(value, refs)
    ---@param o Value
    ---@return Value
    local function walk(o)
        if type(o) == "table" then
            if is_array_like(o) then
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

return NibsUtils

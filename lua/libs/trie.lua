local xxhash64 = require 'xxhash64'
local PrettyPrint = require 'pretty-print'
local p = PrettyPrint.prettyPrint
local colorize = PrettyPrint.colorize

local bit = require 'bit'
local lshift = bit.lshift
local rshift = bit.rshift
local band = bit.band
local bor = bit.bor

local ffi = require 'ffi'
local sizeof = ffi.sizeof
local Slice8 = ffi.typeof 'uint8_t[?]'
local Slice16 = ffi.typeof 'uint16_t[?]'
local Slice32 = ffi.typeof 'uint32_t[?]'
local Slice64 = ffi.typeof 'uint64_t[?]'

--- The internal trie index used by nibs' HAMTrie type
---@class Trie
local Trie = {}

---@class Pointer
---@field hash integer
---@field target integer
local Pointer = {}
Pointer.__index = Pointer
Pointer.__name = "Pointer"

---@param hash integer
---@param target integer
---@return Pointer
function Pointer.new(hash, target)
    return setmetatable({ hash = hash, target = target }, Pointer)
end

---@class Node
---@field bits number
local Node = {}
Node.__index = Node
Node.__name = "Node"
Node.__is_array_like = false

---@param bits number bits for each path segment
function Node.new(bits)
    return setmetatable({ bits = bits }, Node)
end

---Insert an entry into a node
---@param pointer Pointer
---@param depth integer tree depth
---@return integer
function Node:insert(pointer, depth)
    local segment = assert(tonumber(
        band(rshift(pointer.hash, depth * self.bits), lshift(1, self.bits) - 1)
    ))
    ---@type Node|Pointer|nil
    local existing = self[segment]
    if existing then
        local mt = getmetatable(existing)
        if mt == Node then
            return existing:insert(pointer, depth + 1)
        elseif mt == Pointer then
            local child = Node.new(self.bits)
            self[segment] = child
            return 1
                + child:insert(existing, depth + 1)
                + child:insert(pointer, depth + 1)
        end
        error "Bad Type"
    end
    self[segment] = pointer
    return 1
end

function Node:serialize(write)
    -- Serialize subnodes first
    local targets = {}
    for i = lshift(1, self.bits) - 1, 0, -1 do
        ---@type Pointer|Node|nil
        local entry = self[i]
        if entry then
            local mt = getmetatable(entry)
            if mt == Node then
                targets[i] = entry:serialize(write)
            end
        end
    end
    local high = lshift(1, self.bits + 4)
    local bitfield = 0ULL
    local current = write()
    -- Write our own table now
    for i = lshift(1, self.bits) - 1, 0, -1 do
        ---@type Pointer|Node|nil
        local entry = self[i]
        if entry then
            bitfield = bor(bitfield, lshift(1, i))
            local mt = getmetatable(entry)
            if mt == Node then
                local offset = current - targets[i]
                if offset >= high then return nil, "overflow" end
                current = write(bor(high, offset))
            elseif mt == Pointer then
                local target = entry.target
                if target >= high then return nil, "overflow" end
                current = write(target)
            end
        end
    end
    return write(bitfield) -- TODO calculate bitfield
end

---print a colorful hexdump of a string
---@param buf string
local function hex_dump(buf)
    local parts = {}
    for i = 1, math.ceil(#buf / 16) * 16 do
        if (i - 1) % 16 == 0 then
            table.insert(parts, colorize("userdata", string.format('%08x  ', i - 1)))
        end
        table.insert(parts, i > #buf and '   ' or colorize('cdata', string.format('%02x ', buf:byte(i))))
        if i % 8 == 0 then
            table.insert(parts, ' ')
        end
        if i % 16 == 0 then
            table.insert(parts, colorize('braces', buf:sub(i - 16 + 1, i):gsub('%c', '.') .. '\n'))
        end
    end
    print(table.concat(parts))
end

---@param map table<ffi.cdata*,number> map from key slice to number
---@return number seed
---@return number count
---@return number width
---@return ffi.cdata* index as Slice8
local function hamt_encode(map)

    -- Try several combinations of parameters to find the smallest encoding.
    local win = nil
    -- The size of the currently winning index
    local min = 1 / 0
    -- Brute force all hash seeds in the 8-bit keyspace.
    for seed = 0, 255 do
        -- Precompute the hashes outside of the bitsize loop to save CPU.
        local hashes = {}
        for k in pairs(map) do
            hashes[k] = xxhash64(k, assert(sizeof(k)), seed)
        end
        -- Try bit sizes small first and break of first successful encoding.
        for power = 3, 6 do
            -- p { seed = seed, power = power }
            -- Width of pointers in bytes
            local width = lshift(1, power - 3)
            -- Create a new Trie and insert the data
            local trie = Node.new(power)
            -- Count number of rows in the index
            local count = 1
            for k, v in pairs(map) do
                local hash = hashes[k]
                count = count + trie:insert(Pointer.new(hash, v), 0)
            end
            -- Total byte size of index if generated
            local size = count * width

            -- If it looks like this will be a new winner, do the full encoding.
            if size < min then
                local index
                if power == 3 then
                    index = Slice8(count)
                elseif power == 4 then
                    index = Slice16(count)
                elseif power == 5 then
                    index = Slice32(count)
                elseif power == 6 then
                    index = Slice64(count)
                end

                local i = 0
                local _, err = trie:serialize(function(word)
                    if word then
                        i = i + 1
                        -- p("writing", i * width, word, string.format("%08x", tonumber(word)))
                        index[count - i] = word
                    end
                    return (i - 1) * width
                end)
                -- p { size = size, err = err }
                if not err then
                    min = size
                    win = { seed, count, width, index }
                    p { size, win }
                    break
                end
            end
        end
    end
    return unpack(win)
end

local function buf(str)
    return Slice8(#str, str)
end

local sample = {}
for i = 1, 1000 do
    sample[buf('n' .. tostring(i))] = i
end
-- p(sample)
local seed, count, width, index = hamt_encode(sample)


p { seed = seed, count = count, width = width, index = index }
hex_dump(ffi.string(index, ffi.sizeof(index)))

return hamt_encode

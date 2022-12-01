local bit = require 'bit'
local lshift = bit.lshift
local rshift = bit.rshift
local band = bit.band
local bor = bit.bor

local ffi = require 'ffi'
local sizeof = ffi.sizeof

local NibLib = require 'nib-lib'
local Slice8 = NibLib.U8Arr
local Slice16 = NibLib.U16Arr
local Slice32 = NibLib.U32Arr
local Slice64 = NibLib.U64Arr

local xxhash64 = require 'xxhash64'

--- The internal trie index used by nibs' HAMTrie type
local HamtIndex = {}

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
---@field power number
local Node = {}
Node.__index = Node
Node.__name = "Node"
Node.__is_array_like = false

---@param power number bits for each path segment
function Node.new(power)
    return setmetatable({ power = power }, Node)
end

---Insert an entry into a node
---@param pointer Pointer
---@param depth integer tree depth
---@return integer
function Node:insert(pointer, depth)
    local segment = assert(tonumber(
        band(rshift(pointer.hash, depth * self.power), lshift(1, self.power) - 1)
    ))
    ---@type Node|Pointer|nil
    local existing = self[segment]
    if existing then
        local mt = getmetatable(existing)
        if mt == Node then
            return existing:insert(pointer, depth + 1)
        elseif mt == Pointer then
            local child = Node.new(self.power)
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
    local top = lshift(1, self.power) - 1
    for i = top, 0, -1 do
        ---@type Pointer|Node|nil
        local entry = self[i]
        if entry then
            local mt = getmetatable(entry)
            if mt == Node then
                local serialized, err = entry:serialize(write)
                if not serialized then return nil, err end
                targets[i] = serialized
            end
        end
    end
    local high = lshift(1ULL, lshift(1ULL, self.power) - 1)

    local bitfield = 0ULL
    local current = write()
    -- Write our own table now
    for i = top, 0, -1 do
        ---@type Pointer|Node|nil
        local entry = self[i]
        if entry then
            bitfield = bor(bitfield, lshift(1, i))
            local mt = getmetatable(entry)
            if mt == Node then
                local offset = current - targets[i]
                if offset >= high then
                    return nil, "overflow"
                end
                current = write(offset)
            elseif mt == Pointer then
                local target = entry.target
                if target >= high then return nil, "overflow" end
                current = write(bor(high, target))
            end
        end
    end
    return write(bitfield)
end

---@param map table<ffi.cdata*,number> map from key slice to number
---@param optimize number? of hashes to try
---@return number count
---@return number width
---@return ffi.cdata* index as Slice8
function HamtIndex.encode(map, optimize)

    -- Calculate largest output target...
    local max_target = 0
    local count = 0
    for _, v in pairs(map) do
        count = count + 1
        if v > max_target then max_target = v end
    end
    -- ... and use that for the smallest possible start power that works
    local start_power
    if max_target < 0x100 then
        start_power = 3
    elseif max_target < 0x10000 then
        start_power = 4
    elseif max_target < 0x100000000 then
        start_power = 5
    else
        start_power = 6
    end

    if not optimize then
        -- Auto pick a optimize number so massive tries don't use too much CPU
        optimize = math.max(2, math.min(255, 10000000 / (count * count)))
    end

    -- Try several combinations of parameters to find the smallest encoding.
    local win = nil
    -- The size of the currently winning index
    local min = 1 / 0
    -- Brute force all hash seeds in the 8-bit keyspace.
    for seed = 0, optimize do
        -- Precompute the hashes outside of the bitsize loop to save CPU.
        local hashes = {}
        for k in pairs(map) do
            hashes[k] = xxhash64(k, assert(sizeof(k)), seed)
        end
        -- Try bit sizes small first and break of first successful encoding.
        for power = start_power, 6 do

            -- Create a new Trie and insert the data
            local trie = Node.new(power)
            -- Count number of rows in the index
            local count = 1
            for k, v in pairs(map) do
                local hash = hashes[k]
                count = count + trie:insert(Pointer.new(hash, v), 0)
            end

            -- Reserve a slot for the seed
            count = count + 1

            -- Width of pointers in bytes
            local width = lshift(1, power - 3)
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
                local function write(word)
                    if word then
                        i = i + 1
                        index[count - i] = word
                    end
                    return (i - 1) * width
                end

                local _, err = trie:serialize(write)
                write(seed)
                if not err then
                    min = size
                    win = { count, width, index }
                    break
                end
            end
        end
    end
    assert(win, "there was no winner")
    return unpack(win)
end

-- http://graphics.stanford.edu/~seander/bithacks.html#CountBitsSetNaive
local function popcnt(v)
    local c = 0
    while v > 0 do
        c = c + band(v, 1ULL)
        v = rshift(v, 1ULL)
    end
    return c
end

--- Walk a HAMT index checking for matching offset output
---@param read ByteProvider
---@param offset number start of hamt index (including seed)
---@param count number number of pointers in index
---@param width number pointer width in bytes
---@param key ffi.cdata* key
---@return integer? result usually an offset
function HamtIndex.walk(read, offset, count, width, key)
    local omega = offset + count * width
    local bits = assert(width == 1 and 3
        or width == 2 and 4
        or width == 4 and 5
        or width == 8 and 6
        or nil, "Invalid byte width")

    -- Read seed
    local seed = NibLib.decodePointer(read, offset, width)
    offset = offset + width

    local hash = xxhash64(key, assert(ffi.sizeof(key)), seed)

    local segmentMask = lshift(1, bits) - 1
    local highBit = lshift(1ULL, segmentMask)

    while true do

        -- Consume the next path segment
        local segment = band(hash, segmentMask)
        hash = rshift(hash, bits)

        -- Read the next bitfield
        local bitfield = NibLib.decodePointer(read, offset, width)
        offset = offset + width
        assert(offset < omega)

        -- Check if segment is in bitfield
        local match = lshift(1, segment)
        if band(bitfield, match) == 0 then return end

        -- If it is, calculate how many pointers to skip by counting 1s under it.
        local skipCount = tonumber(popcnt(band(bitfield, match - 1)))


        -- Jump to the pointer and read it
        offset = offset + skipCount * width
        assert(offset < omega)
        local ptr = NibLib.decodePointer(read, offset, width)

        -- If there is a leading 1, it's a result pointer.
        if band(ptr, highBit) > 0 then
            return band(ptr, highBit - 1)
        end

        -- Otherwise it's an internal pointer
        offset = offset + width + ptr
        assert(offset < omega)
    end
end

return HamtIndex

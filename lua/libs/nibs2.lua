local p = require('pretty-print').prettyPrint

local xxh64 = require 'xxhash64'

-- Main types
local INT = 0
local FLOAT = 1
local SIMPLE = 2
local REF = 3
local BYTE = 8
local STRING = 9
local LIST = 10
local MAP = 11
local ARRAY = 12
local TRIE = 13
-- Simple subtypes
local FALSE = 0
local TRUE = 1
local NULL = 2

local bit = require 'bit'
local rshift = bit.rshift
local band = bit.band
local lshift = bit.lshift
local bor = bit.bor
local bxor = bit.bxor

local ffi = require 'ffi'
local sizeof = ffi.sizeof
local copy = ffi.copy
local ffi_string = ffi.string
local cast = ffi.cast
local istype = ffi.istype
local metatype = ffi.metatype

local insert = table.insert
local concat = table.concat

local ordered = require 'ordered'
local OrderedMap = ordered.OrderedMap
local OrderedList = ordered.OrderedList

local U8 = ffi.typeof 'uint8_t'
local U16 = ffi.typeof 'uint16_t'
local U32 = ffi.typeof 'uint32_t'
local U64 = ffi.typeof 'uint64_t'
local I8 = ffi.typeof 'int8_t'
local I16 = ffi.typeof 'int16_t'
local I32 = ffi.typeof 'int32_t'
local I64 = ffi.typeof 'int64_t'
local F32 = ffi.typeof 'float'
local F64 = ffi.typeof 'double'

local Slice8 = ffi.typeof 'uint8_t[?]'
local Slice16 = ffi.typeof 'uint16_t[?]'
local Slice32 = ffi.typeof 'uint32_t[?]'
local Slice64 = ffi.typeof 'uint64_t[?]'

local tohex = bit.tohex
local byte = string.byte
local concat = table.concat

local function dump_string(str)
    local parts = {}
    for i = 1, #str do
        parts[i] = tohex(byte(str, i), 2)
    end
    return concat(parts)
end

---Encode a small/big pair into binary parts
---@param small integer any 4-bit unsigned integer
---@param big integer and 64-bit unsigned integer
---@return integer size of encoded bytes
---@return any bytes as parts
local function encode_pair(small, big)
    local pair = lshift(small, 4)
    if big < 0xc then
        return 1, tonumber(bor(pair, big))
    elseif big < 0x100 then
        return 2, Slice8(2, { bor(pair, 12), big })
    elseif big < 0x10000 then
        return 3, { bor(pair, 13), Slice16(1, { big }) }
    elseif big < 0x100000000ULL then
        return 5, { bor(pair, 14), Slice32(1, { big }) }
    else
        return 9, { bor(pair, 15), Slice64(1, { big }) }
    end
end

---@param num integer
---@return integer
local function encode_zigzag(num)
    return num < 0 and num * -2 - 1 or num * 2
end

local converter = ffi.new 'union {double f;uint64_t i;}'
---@param val number
---@return integer
local function encode_float(val)
    converter.f = val
    return converter.i
end

---@type table
---@return boolean
local function is_array_like(val)
    local i = 1
    for key in pairs(val) do
        if key ~= i then return false end
        i = i + 1
    end
    return true
end

---Combine binary parts into a single binary string
---@param size integer total number of expected bytes
---@param parts any parts to combine
---@return string
local function combine(size, parts)
    -- p(size, parts)
    local buf = Slice8(size)
    local offset = 0
    local function write(part)
        local t = type(part)
        if t == "number" then
            buf[offset] = part
            offset = offset + 1
        elseif t == "string" then
            local len = #part
            copy(buf + offset, part, len)
            offset = offset + len
        elseif t == "cdata" then
            local len = sizeof(part)
            copy(buf + offset, part, len)
            offset = offset + len
        elseif t == "table" then
            for _, p in ipairs(part) do
                write(p)
            end
        else
            error("bad type in parts")
        end
    end

    write(parts)
    assert(offset == size)
    return size, buf
end

---@class Nibs
---@field trie_seed integer
local Nibs = {}
local NibsMeta = { __index = Nibs, __name = Nibs }

---@param options? table
---@return Nibs
function Nibs.new(options)
    options = options or {}
    return setmetatable({
        trie_seed = options.trie_seed,
        hash64 = options.hash64,
        to_ref = options.to_ref,
        from_ref = options.from_ref,
        index_limit = options.index_limit,
    }, NibsMeta)
end

Nibs.trie_seed = 0

---Override this in the instance for custom behavior.
Nibs.hash64 = xxh64

---Default index limit that uses indexes when there are more than 10 items.
---Override this in the instance for custom behavior.
---@param size integer
---@param val? table
---@return boolean
function Nibs.index_limit(size, val)
    return val and size > 10
end

---Override this in the instance for custom behavior.
---@param val any potential ref value
---@return integer|nil return an integer to encode value as a ref
function Nibs.to_ref(val) end

---Override this in the instance for custom behavior.
---@param id integer id from encoded ref
---@return any val value of stored ref
function Nibs.from_ref(id)
    error "missing runtime ref system"
end

---Encode any value into a nibs encoded binary string
---@param val any
---@return string
function Nibs:encode(val)
    local size, encoded = combine(self:encode_any(val))
    encoded = ffi_string(encoded, size)
    p(val, dump_string(encoded))
    return encoded
end

---@private
---@param val any
---@return integer size of encoded bytes
---@return any bytes as parts
function Nibs:encode_any(val)
    local id = self.to_ref(val)
    if id then
        return encode_pair(REF, id)
    end

    local t = type(val)
    if t == "number" then
        if val % 1 == 0 then
            return encode_pair(INT, encode_zigzag(val))
        else
            return encode_pair(FLOAT, encode_float(val))
        end
    elseif t == "string" then
        local len = #val
        local size, head = encode_pair(STRING, len)
        return size + len, { head, val }
    elseif t == "cdata" then
        if istype(I64, val) or istype(I32, val) or istype(I16, val) or istype(I8, val) or
            istype(U64, val) or istype(U32, val) or istype(U16, val) or istype(U8, val) then
            -- Treat cdata integers as integers
            return encode_pair(INT, encode_zigzag(val))
        elseif istype(F64, val) or istype(F32, val) then
            -- Treat cdata floats as floats
            return encode_pair(FLOAT, encode_float(val))
        else
            local len = sizeof(val)
            local size, head = encode_pair(BYTE, len)
            return size + len, { head, val }
        end
    elseif t == "boolean" then
        return encode_pair(SIMPLE, val and TRUE or FALSE)
    elseif t == "nil" then
        return encode_pair(SIMPLE, NULL)
    elseif t == "table" then
        local m = getmetatable(val)
        if m == OrderedMap then
            return self:encode_map(val)
        elseif m == OrderedList or is_array_like(val) then
            return self:encode_list(val)
        else
            return self:encode_map(val)
        end
    else
        error(string.format("Unsupported type %s", t))
    end

end

---@private
---@param list any[]
---@return integer
---@return any
function Nibs:encode_list(list)
    local total = 0
    local body = {}
    local offsets = {}
    for i, v in ipairs(list) do
        local size, entry = self:encode_any(v)
        body[i] = entry
        offsets[i] = total
        total = total + size
    end
    local count = #offsets
    if not self.index_limit(count, list) then
        local size, prefix = encode_pair(LIST, total)
        return size + total, { prefix, body }
    end
    local more, index = self.generate_array_index(offsets)
    total = total + more
    local size, prefix = encode_pair(ARRAY, total)
    return size + total, { prefix, index, body }
end

---@private
---@param map table<any,any>
---@return integer
---@return any
function Nibs:encode_map(map)
    local total = 0
    local body = {}
    local offsets = OrderedMap.new()
    local i = 0
    local seed = self.trie_seed
    for k, v in pairs(map) do
        i = i + 1
        local size, entry = combine(self:encode_any(k))

        local h64 = self.hash64(entry, size, seed)
        assert(not offsets[h64], "hash collision")
        offsets[h64] = total

        insert(body, entry)
        total = total + size
        size, entry = self:encode_any(v)
        insert(body, entry)
        total = total + size
    end
    if not self.index_limit(i, map) then
        local size, head = encode_pair(MAP, total)
        return size + total, { head, body }
    end

    local more, index = self.generate_trie_index(offsets, seed)
    total = total + more
    local size, prefix = encode_pair(TRIE, total)
    return size + total, { prefix, index, body }
end

---@private
---@param offsets integer[]
---@return number
---@return any
function Nibs.generate_array_index(offsets)
    local last = 0
    local count = #offsets
    if count > 0 then
        last = offsets[count]
    end
    local index, width
    if last < 0x100 then
        width = 1
        index = Slice8(count, offsets)
    elseif last < 0x10000 then
        width = 2
        index = Slice16(count, offsets)
    elseif last < 0x100000000 then
        width = 4
        index = Slice32(count, offsets)
    else
        width = 8
        index = Slice64(count, offsets)
    end
    local more, head = encode_pair(width, count)
    return more + sizeof(index), { head, index }
end

---@private
---@param offsets table<ffi.cdata*,integer>
---@param seed integer
---@return integer
---@return any
function Nibs.generate_trie_index(offsets, seed)
    local last = 0
    for _, offset in pairs(offsets) do
        last = offset
    end
    local width, Slice, bits
    if last < 0x80 then
        width = 1
        Slice = Slice8
        bits = 3
    elseif last < 0x8000 then
        width = 2
        Slice = Slice16
        bits = 4
    elseif last < 0x80000000 then
        width = 4
        Slice = Slice32
        bits = 5
    else
        width = 8
        Slice = Slice64
        bits = 6
    end
    local mask = U64(lshift(1, bits) - 1)
    local trie = {}
    -- Insert the offsets into the trie
    for h64, offset in pairs(offsets) do
        local o = 0
        local node = trie
        while o < 64 do
            if node.data then
                -- If the node already has data, move it down one
                local data = node.data
                node.data = nil
                node[tonumber(band(rshift(data[1], o), mask))] = { data = data }
                -- And try again
            else
                local segment = tonumber(band(rshift(h64, o), mask))
                if node ~= trie and not next(node) then
                    -- Otherwise, check if node is empty
                    -- and claim it
                    node.data = { h64, offset }
                    break
                end
                -- Or follow/create the next in the path
                local next = node[segment]
                if next then
                    node = next
                else
                    next = {}
                    node[segment] = next
                    node = next
                end
                o = o + bits
            end
        end
    end

    local height = 0
    local parts = {}
    local function write_node(node)
        -- Sort highest first since we're writing backwards
        local segments = {}
        for k in pairs(node) do table.insert(segments, k) end
        table.sort(segments, function(a, b) return a > b end)
        p { segments = segments }

        -- Calculate the target addresses
        local targets = {}
        for i, k in ipairs(segments) do
            local v = node[k]
            if v.data then
                targets[i] = -1 - v.data[2]
            else
                targets[i] = height
                write_node(v)
            end
        end
        p { targets = targets }

        -- Generate the pointers
        local bitfield = 0
        for i, k in ipairs(segments) do
            bitfield = bor(bitfield, lshift(1, k))
            local delta = height - targets[i] - width
            p(height, { key = k, delta = delta })
            table.insert(parts, delta)
            height = height + width
        end

        p(height, { bitfield = bitfield })
        table.insert(parts, bitfield)
        height = height + width


    end

    p { trie = trie }

    write_node(trie)

    p { parts = parts }
    local count = #parts
    local reversed = parts
    parts = {}
    for i = count, 1, -1 do
        parts[count - i + 1] = reversed[i]
    end

    local more, head = encode_pair(width, seed)
    return more + count * width, { head, parts }
end

return Nibs

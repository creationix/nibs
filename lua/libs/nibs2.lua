local xxh64 = require 'xxhash64'

-- Main types
local ZIGZAG = 0
local FLOAT = 1
local SIMPLE = 2
local REF = 3

local BYTES = 8
local UTF8 = 9
local HEXSTRING = 10
local LIST = 11
local MAP = 12
local ARRAY = 13
local TRIE = 14
local SCOPE = 15

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

local Reference, RefScope, Array, Trie

local NibsList, NibsMap, NibsArray, NibsTrie

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

local U8Ptr = ffi.typeof 'uint8_t*'
local U16Ptr = ffi.typeof 'uint16_t*'
local U32Ptr = ffi.typeof 'uint32_t*'
local U64Ptr = ffi.typeof 'uint64_t*'

local Slice8 = ffi.typeof 'uint8_t[?]'
local Slice16 = ffi.typeof 'uint16_t[?]'
local Slice32 = ffi.typeof 'uint32_t[?]'
local Slice64 = ffi.typeof 'uint64_t[?]'

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
    elseif big < 0x100000000 then
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
    local mt = getmetatable(val)
    if mt == OrderedList or mt == NibsList or mt == NibsArray or mt == Array then
        return true
    elseif mt == OrderedMap or mt == NibsMap or mt == NibsTrie or mt == Trie then
        return false
    end
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
---@return number size
---@return ffi.cdata* buffer
local function combine(size, parts)
    ---@type ffi.cdata*
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
            local len = assert(sizeof(part))
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

local encode_any
local encode_list
local encode_map
local encode_array
local generate_array_index
local encode_trie
local generate_trie_index
local encode_scope

---@class Nibs
local Nibs = {}

Nibs.is_array_like = is_array_like

--- A value that can be serialized with nibs
---@alias Value ffi.cdata* | string | number | boolean | nil | RefScope | Reference | table<Value,Value>

--- Class used to store references when encoding.
---@class Reference
---@field index number
Reference = {}
Nibs.Reference = Reference
Reference.__index = Reference
Reference.__name = "Reference"
---Construct a nibs ref instance from a ref index
---@param index number
---@return Reference
function Reference.new(index)
    return setmetatable({ index = index }, Reference)
end

function Reference:__tostring()
    return "&" .. self.index
end

--- Scope used to encode references.
---@class RefScope
---@field value Value
---@field refs Value[]
RefScope = {}
Nibs.RefScope = RefScope
RefScope.__index = RefScope
RefScope.__name = "RefScope"
function RefScope:__index(k)
    return self.value[k]
end

function RefScope:__newindex(k, v)
    self.value[k] = v
end

function RefScope:__len()
    return #self.value
end

function RefScope:__pairs()
    return pairs(self.value)
end

function RefScope:__ipairs()
    return ipairs(self.value)
end

---Construct a nibs ref scope from a list of values to be referenced and a child value
---@param value Value Child value that may use refs from this scope
---@param refs Value[] list of values that can be referenced
function RefScope.new(value, refs)
    return setmetatable({ value = value, refs = refs }, RefScope)
end

---@class Array
---@field list Value[]
Array = {}
Nibs.Array = Array
Array.__index = Array
Array.__name = "Array"
---Mark a list as needing array index when encoding.
---@param list Value[]
function Array.new(list)
    return setmetatable({ list = list }, Array)
end

---@class Trie
---@field map table<Value,Value>
---@field seed integer
---@field optimize number
Trie = {}
Nibs.Trie = Trie
Trie.__index = Trie
Trie.__name = "Trie"
---Mark a list as needing trie index when encoding.
---@param map table<Value,Value>
---@param seed integer initial seed to use for key hash
---@param optimize integer amount of sequential seeds to try before picking best
function Trie.new(map, seed, optimize)
    return setmetatable({ map = map, seed = seed or 0, optimize = optimize or 10 }, Trie)
end

---Encode any value into a nibs encoded binary string
---@param val Value
---@return string
function Nibs.encode(val)
    local size, encoded = combine(encode_any(val))
    return ffi_string(encoded, size)
end

-- Needs to be only done once
local hex_to_char = {}
for idx = 0, 255 do
    hex_to_char[("%02X"):format(idx)] = string.char(idx)
    hex_to_char[("%02x"):format(idx)] = string.char(idx)
end

local function hex_decode(val)
    return (val:gsub("(..)", hex_to_char))
end

---@param val any
---@return integer size of encoded bytes
---@return any bytes as parts
function encode_any(val)

    local t = type(val)
    if t == "number" then
        if val % 1 == 0 then
            return encode_pair(ZIGZAG, encode_zigzag(val))
        else
            return encode_pair(FLOAT, encode_float(val))
        end
    elseif t == "string" then
        local len = #val
        if len % 2 == 0 and string.match(val, "^[0-9a-f]+$") then
            len = len / 2
            local size, head = encode_pair(HEXSTRING, len)
            return size + len, { head, hex_decode(val) }
        end
        local size, head = encode_pair(UTF8, len)
        return size + len, { head, val }
    elseif t == "cdata" then
        if istype(I64, val) or istype(I32, val) or istype(I16, val) or istype(I8, val) or
            istype(U64, val) or istype(U32, val) or istype(U16, val) or istype(U8, val) then
            -- Treat cdata integers as integers
            return encode_pair(ZIGZAG, encode_zigzag(val))
        elseif istype(F64, val) or istype(F32, val) then
            -- Treat cdata floats as floats
            return encode_pair(FLOAT, encode_float(val))
        else
            local len = sizeof(val)
            local size, head = encode_pair(BYTES, len)
            return size + len, { head, val }
        end
    elseif t == "boolean" then
        return encode_pair(SIMPLE, val and TRUE or FALSE)
    elseif t == "nil" then
        return encode_pair(SIMPLE, NULL)
    elseif t == "table" then
        local mt = getmetatable(val)
        if mt == Reference then
            return encode_pair(REF, val.index)
        elseif mt == RefScope then
            return encode_scope(val)
        elseif mt == Array then
            return encode_array(val)
        elseif mt == Trie then
            return encode_trie(val)
        else
            if is_array_like(val) then
                return encode_list(val)
            else
                return encode_map(val)
            end
        end
    else
        return encode_any(tostring(val))
    end

end

---@param list Value[]
---@return integer
---@return any
function encode_list(list)
    local total = 0
    local body = {}
    for i, v in ipairs(list) do
        local size, entry = encode_any(v)
        body[i] = entry
        total = total + size
    end
    local size, prefix = encode_pair(LIST, total)
    return size + total, { prefix, body }
end

---@param array Array
---@return integer
---@return any
function encode_array(array)
    local list = array.list
    local total = 0
    local body = {}
    local offsets = {}
    for i, v in ipairs(list) do
        local size, entry = encode_any(v)
        body[i] = entry
        offsets[i] = total
        total = total + size
    end
    local more, index = generate_array_index(offsets)
    total = total + more
    local size, prefix = encode_pair(ARRAY, total)
    return size + total, { prefix, index, body }
end

---@param scope RefScope
---@return integer
---@return any
function encode_scope(scope)
    local total = 0
    local body = {}
    local offsets = {}
    local size, value_entry = encode_any(scope.value)
    total = total + size
    for i, v in ipairs(scope.refs) do
        local entry
        size, entry = encode_any(v)
        body[i] = entry
        offsets[i] = total
        total = total + size
    end
    local more, index = generate_array_index(offsets)
    total = total + more
    local size, prefix = encode_pair(SCOPE, total)
    return size + total, { prefix, index, value_entry, body }
end

---@param map table<Value,Value>
---@return integer
---@return any
function encode_map(map)
    local total = 0
    local body = {}
    for k, v in pairs(map) do
        local size, entry = combine(encode_any(k))
        insert(body, entry)
        total = total + size
        size, entry = encode_any(v)
        insert(body, entry)
        total = total + size
    end
    local size, head = encode_pair(MAP, total)
    return size + total, { head, body }
end

---@param trie Trie
---@return integer
---@return any
function encode_trie(trie)
    local map = trie.map
    local seed = trie.seed
    local optimize = trie.optimize
    local total = 0
    local body = {}
    local offsets = OrderedMap.new()
    local i = 0
    for k, v in pairs(map) do
        i = i + 1
        local size, entry = combine(encode_any(k))

        local key = { entry, size }
        offsets[key] = total

        insert(body, entry)
        total = total + size
        size, entry = encode_any(v)
        insert(body, entry)
        total = total + size
    end

    local more, index = generate_trie_index(offsets, seed, optimize)
    total = total + more
    local size, prefix = encode_pair(TRIE, total)
    return size + total, { prefix, index, body }
end

---@private
---@param offsets integer[]
---@return number
---@return any
function generate_array_index(offsets)
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

local function build_trie(inputs, bits, hash64, seed)
    local mask = U64(lshift(1, bits) - 1)
    local trie = {}
    local count = 0
    -- Insert the offsets into the trie
    for key, offset in pairs(inputs) do
        local ptr, len = unpack(key)
        local hash = hash64(ptr, len, seed)
        local o = 0
        local node = trie
        while o < 64 do
            if type(node[2]) == "number" then
                -- If the node already has data, move it down one
                local has, off = node[1], node[2]
                node[1], node[2] = nil, nil
                node[tonumber(band(rshift(has, o), mask))] = { has, off }
                count = count + 1
                -- And try again
            else
                local segment = tonumber(band(rshift(hash, o), mask))
                if node ~= trie and not next(node) then
                    -- Otherwise, check if node is empty
                    -- and claim it
                    node[1], node[2] = hash, offset
                    break
                end
                -- Or follow/create the next in the path
                local next = node[segment]
                if next then
                    node = next
                else
                    next = {}
                    count = count + 1
                    node[segment] = next
                    node = next
                end
                o = o + bits
            end
        end
    end
    return trie, count
end

---@private
---@param offsets table<ffi.cdata*,integer>
---@param seed integer
---@param optimize integer
---@return integer
---@return any
function generate_trie_index(offsets, seed, optimize)
    local last = 0
    for _, offset in pairs(offsets) do
        last = offset
    end
    local Slice, bits
    if last < 0x80 then
        Slice = Slice8
        bits = 3
    elseif last < 0x8000 then
        Slice = Slice16
        bits = 4
    elseif last < 0x80000000 then
        Slice = Slice32
        bits = 5
    else
        Slice = Slice64
        bits = 6
    end
    local width = lshift(1, bits - 3)
    local mod = lshift(1ULL, U64(width * 8))

    local min, win, ss
    for i = 0, optimize do
        local s = (seed + i) % mod
        local trie, count = build_trie(offsets, bits, xxh64, s)
        if not win or count < min then
            win = trie
            min = count
            ss = s
        end
    end
    local trie = win
    seed = ss

    local height = 0
    local parts = {}
    local function write_node(node)
        -- Sort highest first since we're writing backwards
        local segments = {}
        for k in pairs(node) do table.insert(segments, k) end
        table.sort(segments, function(a, b) return a > b end)

        -- Calculate the target addresses
        local targets = {}
        for i, k in ipairs(segments) do
            local v = node[k]
            if type(v[2]) == "number" then
                targets[i] = -1 - v[2]
            else
                targets[i] = height
                write_node(v)
            end
        end
        -- p { targets = targets }

        -- Generate the pointers
        local bitfield = U64(0)
        for i, k in ipairs(segments) do
            bitfield = bor(bitfield, lshift(1, k))
            local target = targets[i]
            if target >= 0 then
                target = height - target - width
            end
            -- p(height, { segment = k, pointer = target })
            table.insert(parts, target)
            height = height + width
        end

        -- p(height, { bitfield = bit.tohex(bitfield) })
        table.insert(parts, bitfield)
        height = height + width


    end

    -- p { trie = trie }

    write_node(trie)

    -- p { parts = parts }
    table.insert(parts, seed)
    local count = #parts
    local slice = Slice(count)
    for i, part in ipairs(parts) do
        slice[count - i] = part
    end

    local index_width = count * width
    assert(sizeof(slice) == index_width)

    local more, head = encode_pair(width, index_width)
    return more + index_width, { head, slice }
end

---@param read ByteProvider
---@param offset number
---@return number
---@return number
---@return number
local function decode_pair(read, offset)
    local data = read(tonumber(offset), 9)
    local ptr = cast(U8Ptr, data)
    local head = ptr[0]
    local little = rshift(head, 4)
    local big = band(head, 0xf)
    if big == 0xc then
        return offset + 2, little, ptr[1]
    elseif big == 0xd then
        return offset + 3, little, cast(U16Ptr, ptr + 1)[0]
    elseif big == 0xe then
        return offset + 5, little, cast(U32Ptr, ptr + 1)[0]
    elseif big == 0xf then
        return offset + 9, little, cast(U64Ptr, ptr + 1)[0]
    else
        return offset + 1, little, big
    end
end

local function tonumberMaybe(n)
    local nn = tonumber(n)
    return nn == n and nn or n
end

---Convert a nibs big from zigzag to I64
---@param big integer
---@return integer
local function decode_zigzag(big)
    local i = I64(big)
    return tonumberMaybe(bxor(rshift(i, 1), -band(i, 1)))
end

local converter = ffi.new 'union {double f;uint64_t i;}'

local function decode_float(val)
    converter.i = val
    return converter.f
end

local function decode_simple(big)
    if big == FALSE then
        return false
    elseif big == TRUE then
        return true
    elseif big == NULL then
        return nil
    end
    error(string.format("Invalid simple type %d", big))
end

---@param read ByteProvider
---@param offset number
---@param length number
---@return ffi.ctype*
local function decode_bytes(read, offset, length)
    local data = read(offset, length)
    local ptr = cast(U8Ptr, data)
    local bytes = Slice8(length)
    copy(bytes, ptr, length)
    return bytes
end

---@param read ByteProvider
---@param offset number
---@param length number
---@return string
local function decode_string(read, offset, length)
    return read(offset, length)
end

-- Convert integer to ascii code for hex digit
local function tohex(num)
    return num + (num < 10 and 48 or 87)
end

---@param read ByteProvider
---@param offset number
---@param length number
---@return string
local function decode_hexstring(read, offset, length)
    local bytes = read(offset, length)
    local chars = Slice8(length * 2)
    for i = 1, length do
        local b = string.byte(bytes, i, i)
        chars[i * 2 - 2] = tohex(rshift(b, 4))
        chars[i * 2 - 1] = tohex(band(b, 15))
    end
    return ffi.string(chars, length * 2)
end

local function decode_pointer(read, offset, width)
    local str = read(offset, width)
    if width == 1 then return cast(U8Ptr, str)[0] end
    if width == 2 then return cast(U16Ptr, str)[0] end
    if width == 4 then return cast(U32Ptr, str)[0] end
    if width == 8 then return cast(U64Ptr, str)[0] end
    error("Illegal pointer width " .. width)
end

local function skip(read, offset)
    local little, big
    offset, little, big = decode_pair(read, offset)
    if little < 8 then
        return offset
    else
        return offset + big
    end
end

local UintPtrs = {
    [3] = U8Ptr,
    [4] = U16Ptr,
    [5] = U32Ptr,
    [6] = U64Ptr,
}
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
---@param offset number
---@param hash integer u64 hash of key
---@param bits number bits per path segment (3 for 8 bit, 4 for 16 bit, etc...)
---@return integer? result usually an offset
local function hamtWalk(read, offset, hash, bits)
    local UintPtr = assert(UintPtrs[bits], "Invalid segment bit width")
    local width = lshift(1, bits - 3)
    local segmentMask = lshift(1, bits) - 1
    local highBit = lshift(1ULL, segmentMask)

    while true do

        -- Consume the next path segment
        local segment = band(hash, segmentMask)
        hash = rshift(hash, bits)

        -- Read the next bitfield
        local bitfield = cast(UintPtr, read(offset, width))[0]
        offset = offset + width

        -- Check if segment is in bitfield
        local match = lshift(1, segment)
        if band(bitfield, match) == 0 then return end

        -- If it is, calculate how many pointers to skip by counting 1s under it.
        local skipCount = tonumber(popcnt(band(bitfield, match - 1)))

        -- Jump to the pointer and read it
        offset = offset + skipCount * width
        local ptr = cast(U8Ptr, read(offset, width))[0]

        -- If there is a leading 1, it's a result pointer.
        if band(ptr, highBit) > 0 then
            return band(ptr, highBit - 1)
        end

        -- Otherwise it's an internal pointer
        offset = offset + 1 + ptr
    end
end

local get

---@class NibsMetaEntry
---@field read ByteProvider
---@field scope DecodeScope? optional ref scope chain
---@field alpha number start of data as offset
---@field omega number end of data as offset to after data
---@field width number? width of index entries
---@field count number? count of index entries
---@field seed number? hash seed for trie hamt

-- Weakmap for associating private metadata to tables.
---@type table<table,NibsMetaEntry>
local NibsMeta = setmetatable({}, { __mode = "k" })

---@class NibsList
NibsList = {}
NibsList.__name = "NibsList"

---@param read ByteProvider
---@param offset number
---@param length number
---@param scope DecodeScope?
---@return NibsList
function NibsList.new(read, offset, length, scope)
    local self = setmetatable({}, NibsList)
    NibsMeta[self] = {
        read = read,
        scope = scope,
        alpha = offset, -- Start of list values
        omega = offset + length, -- End of list values
    }
    return self
end

function NibsList:__len()
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    local count = rawget(self, "len")
    if not count then
        count = 0
        while offset < meta.omega do
            offset = skip(read, offset)
            count = count + 1
        end
        rawset(self, "len", count)
    end
    return count
end

function NibsList:__index(idx)
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    local count = 1
    while offset < meta.omega and count < idx do
        offset = skip(read, offset)
        count = count + 1
    end
    if count == idx then
        local value = get(read, offset, meta.scope)
        rawset(self, idx, value)
        return value
    end
end

function NibsList:__ipairs()
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    local count = 0
    return function()
        if offset < meta.omega then
            count = count + 1
            local value = rawget(self, count)
            if value then
                offset = skip(read, offset)
            else
                value, offset = get(read, offset, meta.scope)
                rawset(self, count, value)
            end
            return count, value
        end
    end
end

NibsList.__pairs = NibsList.__ipairs

function NibsList:__tostring()
    local parts = { "[" }
    for i, v in ipairs(self) do
        if i > 1 then
            insert(parts, ",")
        end
        insert(parts, tostring(v))
    end
    insert(parts, "]")
    return concat(parts)
end

---@class NibsMap
NibsMap = {}
NibsMap.__name = "NibsMap"

---@param read ByteProvider
---@param offset number
---@param length number
---@param scope DecodeScope?
---@return NibsMap
function NibsMap.new(read, offset, length, scope)
    local self = setmetatable({}, NibsMap)
    NibsMeta[self] = {
        read = read,
        scope = scope,
        alpha = offset, -- Start of map values
        omega = offset + length, -- End of map values
    }
    return self
end

function NibsMap:__len()
    return 0
end

function NibsMap:__pairs()
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    return function()
        if offset < meta.omega then
            local key, value
            key, offset = get(read, offset, meta.scope)
            value = rawget(self, key)
            if value then
                offset = skip(read, offset)
            else
                value, offset = get(read, offset, meta.scope)
                rawset(self, key, value)
            end
            return key, value
        end
    end
end

function NibsMap:__index(idx)
    local meta = NibsMeta[self]
    local offset = meta.alpha
    local read = meta.read
    while offset < meta.omega do
        local key
        key, offset = get(read, offset, meta.scope)
        if key == idx then
            local value = get(read, offset, meta.scope)
            rawset(self, idx, value)
            return value
        else
            offset = skip(read, offset)
        end
    end
end

function NibsMap:__tostring()
    local parts = { "{" }
    local first = true
    for k, v in pairs(self) do
        if not first then
            insert(parts, ",")
        end
        first = false
        insert(parts, tostring(k) .. ":" .. tostring(v))
    end
    insert(parts, "}")
    return concat(parts)
end

---@class NibsArray
NibsArray = {}
NibsArray.__name = "NibsArray"

---@param read ByteProvider
---@param offset number
---@param length number
---@param scope DecodeScope?
---@return NibsArray
function NibsArray.new(read, offset, length, scope)
    local self = setmetatable({}, NibsArray)
    local alpha, width, count = decode_pair(read, offset)
    local omega = offset + length
    NibsMeta[self] = {
        read = read,
        scope = scope,
        alpha = alpha, -- Start of array index
        omega = omega, -- End of array values
        width = width, -- Width of index entries
        count = count, -- Count of index entries
    }
    return self
end

function NibsArray:__index(idx)
    local meta = NibsMeta[self]
    if idx < 1 or idx > meta.count or math.floor(idx) ~= idx then return end
    local offset = meta.alpha + (idx - 1) * meta.width
    local ptr = decode_pointer(meta.read, offset, meta.width)
    offset = meta.alpha + (meta.width * meta.count) + ptr
    local value = get(meta.read, offset, meta.scope)
    return value
end

function NibsArray:__len()
    local meta = NibsMeta[self]
    return meta.count
end

function NibsArray:__ipairs()
    local i = 0
    local count = #self
    return function()
        if i < count then
            i = i + 1
            return i, self[i]
        end
    end
end

NibsArray.__pairs = NibsArray.__ipairs

NibsArray.__tostring = NibsList.__tostring

---@class NibsTrie
NibsTrie = {}
NibsTrie.__name = "NibsTrie"

---@param read ByteProvider
---@param offset number
---@param length number
---@param scope DecodeScope?
---@return NibsTrie
function NibsTrie.new(read, offset, length, scope)
    local self = setmetatable({}, NibsTrie)
    local alpha, width, count = decode_pair(read, offset)
    local seed = decode_pointer(read, alpha, width)
    local omega = offset + length
    NibsMeta[self] = {
        read = read,
        scope = scope,
        alpha = alpha, -- Start of trie index
        omega = omega, -- End of trie values
        seed = seed, -- Seed for HAMT
        width = width, -- Width of index entries
        count = count, -- Count of index entries
    }
    return self
end

function NibsTrie:__index(idx)
    local meta = NibsMeta[self]
    local read = meta.read
    local offset = meta.alpha + meta.width
    local encoded = nibs:encode(idx)
    local hash = xxh64(cast(U8Ptr, encoded), #encoded, meta.seed)

    local bits = assert(meta.width == 1 and 3
        or meta.width == 2 and 4
        or meta.width == 4 and 5
        or meta.width == 8 and 6
        or nil, "Invalid byte width")

    local target = hamtWalk(read, offset, hash, bits)
    if not target then return end

    target = tonumber(target)

    offset = meta.alpha + meta.width * meta.count + target
    local key, value
    key, offset = get(read, offset, meta.scope)
    if key ~= idx then return end

    value = get(read, offset, meta.scope)
    return value
end

function NibsTrie:__len()
    return 0
end

function NibsTrie:__pairs()
    local meta = NibsMeta[self]
    local offset = meta.alpha + meta.width * meta.count
    return function()
        if offset < meta.omega then
            local key, value
            key, offset = get(meta.read, offset, meta.scope)
            value, offset = get(meta.read, offset, meta.scope)
            return key, value
        end
    end
end

NibsTrie.__tostring = NibsMap.__tostring

---@class DecodeScope
---@field parent DecodeScope?
---@field alpha number
---@field omega number
---@field width number
---@field count number

local function decode_scope(read, offset, big, scope)
    local alpha, width, count = decode_pair(read, offset)
    return get(read, alpha + width * count, {
        parent = scope,
        alpha = alpha,
        omega = offset + big,
        width = width,
        count = count
    })
end

local function decode_ref(read, scope, big)
    assert(scope, "Ref found outside of scope")
    local ptr = decode_pointer(read, scope.alpha + big * scope.width, scope.width)
    local start = scope.alpha + scope.width * scope.count + ptr
    return get(read, start)
end

---Read a nibs value at offset
---@param read ByteProvider
---@param offset number
---@param scope DecodeScope?
---@return any, number
function get(read, offset, scope)
    local little, big
    offset, little, big = decode_pair(read, offset)
    if little == ZIGZAG then
        return decode_zigzag(big), offset
    elseif little == FLOAT then
        return decode_float(big), offset
    elseif little == SIMPLE then
        return decode_simple(big), offset
    elseif little == REF then
        return decode_ref(read, scope, big), offset
    elseif little == BYTES then
        return decode_bytes(read, offset, big), offset + big
    elseif little == UTF8 then
        return decode_string(read, offset, big), offset + big
    elseif little == HEXSTRING then
        return decode_hexstring(read, offset, big), offset + big
    elseif little == LIST then
        return NibsList.new(read, offset, big, scope), offset + big
    elseif little == MAP then
        return NibsMap.new(read, offset, big, scope), offset + big
    elseif little == ARRAY then
        return NibsArray.new(read, offset, big, scope), offset + big
    elseif little == TRIE then
        return NibsTrie.new(read, offset, big, scope), offset + big
    elseif little == SCOPE then
        return decode_scope(read, offset, big, scope), offset + big
    else
        error('Unexpected nibs type: ' .. little)
    end
end

Nibs.get = get

return Nibs

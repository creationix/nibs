local PrettyPrint = require 'pretty-print'
local p = PrettyPrint.prettyPrint

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

local insert = table.insert
local sort = table.sort
local unpack = table.unpack

local Ordered = require 'ordered'
local OrderedList = Ordered.List
local OrderedMap = Ordered.Map
local OrderedArray = Ordered.Array
local OrderedTrie = Ordered.Trie
local Ref = Ordered.Ref
local RefScope = Ordered.RefScope
local is_array_like = Ordered.__is_array_like

local xxh64 = require 'xxhash64'

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

--- A value that can be serialized with nibs
---@alias Value ffi.cdata* | string | number | boolean | nil | RefScope | Ref | table<Value,Value>

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
            local len = assert(sizeof(val))
            local size, head = encode_pair(BYTES, len)
            return size + len, { head, val }
        end
    elseif t == "boolean" then
        return encode_pair(SIMPLE, val and TRUE or FALSE)
    elseif t == "nil" then
        return encode_pair(SIMPLE, NULL)
    elseif t == "table" then
        local mt = getmetatable(val)
        if mt == Ref then
            return encode_pair(REF, val[1])
        elseif mt == RefScope then
            return encode_scope(val)
        elseif is_array_like(val) then
            if mt and mt.__is_indexed then
                return encode_array(val)
            end
            return encode_list(val)
        else
            if mt and mt.__is_indexed then
                return encode_trie(val)
            end
            return encode_map(val)
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

---@param list Value[]
---@param tag number?
---@return integer
---@return any
function encode_array(list, tag)
    tag = tag or ARRAY
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
    local size, prefix = encode_pair(tag, total)
    return size + total, { prefix, index, body }
end

---@param scope RefScope
---@return integer
---@return any
function encode_scope(scope)
    return encode_array(scope, SCOPE)
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

---@param map table<Value,Value>
---@return integer
---@return any
function encode_trie(map)
    local seed = 2 -- TODO find way to configure this option
    local optimize = 0 -- TODO find way to configure this option
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
    local count = 1
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
                count = count + 2
                -- And try again
            else
                local segment = assert(tonumber(band(rshift(hash, o), mask)))
                if node ~= trie and not next(node) then
                    -- Otherwise, check if node is empty
                    -- and claim it
                    node[1], node[2] = hash, offset
                    count = count + 1
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
    local high = lshift(1ULL, U64(width * 8) - 1)

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
        for k in pairs(node) do insert(segments, k) end
        sort(segments, function(a, b) return a > b end)

        -- Calculate the target addresses
        local targets = {}
        for i, k in ipairs(segments) do
            local v = node[k]
            if type(v[2]) == "number" then
                assert(v[2] < high, "Target too high for pointer width")
                targets[i] = bor(v[2], high)
            else
                write_node(v)
                assert(height < high, "Index too tall for pointer width")
                targets[i] = height
            end
        end

        -- Generate the pointers
        local bitfield = U64(0)
        for i, k in ipairs(segments) do
            bitfield = bor(bitfield, lshift(1, k))
            local target = targets[i]
            if target < high then
                target = height - target
                assert(target < high, "Internal pointer too big for pointer width")
            end
            insert(parts, target)
            height = height + width
        end

        insert(parts, bitfield)
        -- print(string.format("writing bitfield %02x", tonumber(bitfield)))
        height = height + width


    end

    write_node(trie)

    insert(parts, seed)
    local count = #parts
    local slice = Slice(count)
    for i, part in ipairs(parts) do
        slice[count - i] = part
    end

    local index_width = count * width
    assert(sizeof(slice) == index_width)

    local more, head = encode_pair(width, count)
    return more + index_width, { head, slice }
end

---@param read ByteProvider
---@param offset number
---@return number
---@return number
---@return number
local function decode_pair(read, offset)
    local data = read(assert(tonumber(offset)), 9)
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
---@param hash integer u64 hash of key
---@param offset number start of hamt index (after seed)
---@param omega number end of hamt index (before payload)
---@param width number pointer width in bytes
---@return integer? result usually an offset
local function hamtWalk(read, hash, offset, omega, width)
    local bits = assert(width == 1 and 3
        or width == 2 and 4
        or width == 4 and 5
        or width == 8 and 6
        or nil, "Invalid byte width")

    local segmentMask = lshift(1, bits) - 1
    local highBit = lshift(1ULL, segmentMask)

    while true do

        -- Consume the next path segment
        local segment = band(hash, segmentMask)
        hash = rshift(hash, bits)

        -- Read the next bitfield

        local bitfield = decode_pointer(read, offset, width)
        -- print(string.format("bitfield=%02x popcnt=%d", bitfield, tonumber(popcnt(bitfield))))
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
        local ptr = decode_pointer(read, offset, width)

        -- If there is a leading 1, it's a result pointer.
        if band(ptr, highBit) > 0 then
            return band(ptr, highBit - 1)
        end

        -- Otherwise it's an internal pointer
        offset = offset + width + ptr
        assert(offset < omega)
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
NibsList.__is_array_like = true

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

function NibsList.__newindex()
    error "NibsList is read-only"
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

---@class NibsMap
NibsMap = {}
NibsMap.__name = "NibsMap"
NibsMap.__is_array_like = false

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

function NibsMap.__len()
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

function NibsMap.__newindex()
    error "NibsMap is read-only"
end

---@class NibsArray
NibsArray = {}
NibsArray.__name = "NibsArray"
NibsArray.__is_array_like = true
NibsArray.__is_indexed = true

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

function NibsArray.__newindex()
    error "NibsArray is read-only"
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

---@class NibsTrie
NibsTrie = {}
NibsTrie.__name = "NibsTrie"
NibsTrie.__is_array_like = false
NibsTrie.__is_indexed = true

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
    local width = assert(meta.width)
    local offset = meta.alpha + width -- start after seed at first bitfield
    local encoded = Nibs.encode(idx)
    local hash = xxh64(cast(U8Ptr, encoded), #encoded, meta.seed)

    local target = hamtWalk(read, hash, offset, meta.omega, width)
    if not target then return end

    target = tonumber(target)

    offset = meta.alpha + meta.width * meta.count + target
    local key, value
    key, offset = get(read, offset, meta.scope)
    if key ~= idx then return end

    value = get(read, offset, meta.scope)
    return value
end

function NibsTrie.__newindex()
    error "NibsTrie is read-only"
end

function NibsTrie.__len()
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
            -- TODO: remove this sanity check once we're confident in __index
            local check = self[key]
            if not (type(value) == "table" or type(value) == "cdata" or check == value) then
                p("MISMATCH", key, value, check)
                error "Mismatch"
            end
            return key, value
        end
    end
end

---@class DecodeScope
---@field parent DecodeScope?
---@field alpha number
---@field omega number
---@field width number
---@field count number

local function decode_scope(read, offset, big, scope)
    local alpha, width, count = decode_pair(read, offset)
    -- nested Value is the last ref
    local ptr = decode_pointer(read, alpha + width * (count - 1), width)
    return get(read, alpha + width * count + ptr, {
        parent = scope,
        alpha = alpha,
        omega = offset + big,
        width = width,
        count = count
    })
end

---@param read ByteProvider
---@param scope? DecodeScope
---@param big integer
---@return any
local function decode_ref(read, scope, big)
    assert(scope, "Ref found outside of scope")
    local ptr = decode_pointer(read, scope.alpha + big * scope.width, scope.width)
    local payload = scope.alpha + scope.width * scope.count
    local start = payload + ptr
    return (get(read, start, scope))
end

---Read a nibs value at offset
---@param read ByteProvider
---@param offset number
---@param scope DecodeScope?
---@return any, number
function get(read, offset, scope)
    local start = offset
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
        error(string.format('Unexpected nibs type: %s at %08x', little, start))
    end
end

Nibs.get = get

---Decode a nibs string from memory
---@param str string
---@return any
function Nibs.decode(str)
    local val, offset = Nibs.get(function(offset, length)
        return string.sub(str, offset + 1, offset + length)
    end, 0)
    assert(offset == #str, "extra data in input string")
    return val
end

---Turn lists and maps into arrays and tries if they are over some limit
---@param value Value
---@param index_limit number
function Nibs.autoIndex(value, index_limit)
    index_limit = index_limit or 10

    ---@param o Value
    local function walk(o)
        if type(o) ~= "table" then return o end
        local mt = getmetatable(o)
        if mt == Ref then
            return o
        elseif mt == RefScope then
            local last = #o
            o[last] = walk(o[last])
            return o
        end
        if is_array_like(o) then
            if #o < index_limit then
                for i = 1, #o do
                    o[i] = walk(o[i])
                end
                return o
            else
                local r = OrderedArray.new()
                for i = 1, #o do
                    r[i] = walk(o[i])
                end
                return r
            end
        end
        local count = 0
        for _ in pairs(o) do count = count + 1 end
        if count < index_limit then
            for k, v in pairs(o) do
                o[walk(k)] = walk(v)
            end
            return o
        else
            local r = OrderedTrie.new()
            for k, v in pairs(o) do
                r[walk(k)] = walk(v)
            end
            return r
        end
    end

    return walk(value)
end

---Walk through a value and replace values found in the reference table with refs.
---@param value Value
---@param refs Value[]
function Nibs.addRefs(value, refs)
    if #refs == 0 then return value end
    ---@param o Value
    ---@return Value
    local function walk(o)
        if type(o) == "table" then
            if getmetatable(o) == RefScope then return o end
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
                return Ref.new(i - 1)
            end
        end
        return o
    end

    refs[#refs + 1] = walk(value)
    return RefScope.new(refs)
end

---Walk through a value and find duplicate values (sorted by frequency)
---@param value Value
---@retun Value[]
function Nibs.findDuplicates(value)
    -- Wild guess, but real data with lots of dups over 1mb is 1 for reference
    local pointer_cost = 1
    local small_string = pointer_cost + 1
    local small_number = lshift(1, lshift(pointer_cost, 3) - 1)
    local function potentiallyBig(val)
        local t = type(val)
        if t == "string" then
            return #val > small_string
        elseif t == "number" then
            return math.floor(val) ~= val or val <= -small_number or val > small_number
        end
        return false
    end

    local seen = {}
    local duplicates = {}
    local total_encoded_size = 0
    ---@param o Value
    ---@return Value
    local function walk(o)
        if type(o) == "table" then
            -- Don't walk into nested scopes
            if getmetatable(o) == RefScope then return o end
            for k, v in pairs(o) do
                walk(k)
                walk(v)
            end
        elseif o and potentiallyBig(o) then
            local old = seen[o]
            if not old then
                seen[o] = 1
            else
                if old == 1 then
                    total_encoded_size = total_encoded_size + #Nibs.encode(o)
                    table.insert(duplicates, o)
                end
                seen[o] = old + 1
            end
        end
    end

    -- Extract all duplicate values that can be potentially saved
    walk(value)

    -- Update pointer cost based on real data we now have
    -- note this is still not 100% accurate as we still need to prune any
    -- potential refs that are not worth adding and that pruning may
    -- drop this down a level.
    pointer_cost = total_encoded_size < 0x100 and 1
        or total_encoded_size < 0x10000 and 2
        or total_encoded_size < 0x100000000 and 4
        or 8

    -- Sort by frequency
    table.sort(duplicates, function(a, b)
        return seen[a] > seen[b]
    end)

    -- Remove any entries that cost more than they save
    local trimmed = {}
    local i = 0
    for _, v in ipairs(duplicates) do
        local cost = #Nibs.encode(v)
        local refCost = i < 12 and 1
            or i < 0x100 and 2
            or i < 0x10000 and 3
            or i < 0x100000000 and 5
            or 9
        local count = seen[v]
        if refCost * count + pointer_cost < cost * count then
            i = i + 1
            trimmed[i] = v
        end
    end

    -- This final list is guranteed to not contain any values that bloat the final size
    -- by turning into refs, but it had a chance to miss some it should have included.
    return trimmed
end

function Nibs.deduplicate(val)
    return Nibs.addRefs(val, Nibs.findDuplicates(val))
end

return Nibs

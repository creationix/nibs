--[[lit-meta
    name = "creationix/nibs"
    version = "1.1.0"
    homepage = "https://github.com/creationix/nibs"
    description = "An implementation of nibs serialization format for luajit."
    tags = {"nibs","serialization","jit"}
    license = "MIT"
    author = { name = "Tim Caswell" }
]]

local Ordered = require 'ordered'
local OrderedMap = Ordered.OrderedMap
local OrderedList = Ordered.OrderedList

local bit = require 'bit'
local rshift = bit.rshift
local band = bit.band
local lshift = bit.lshift
local bor = bit.bor
local bxor = bit.bxor
local tohex = bit.tohex

local ffi = require 'ffi'
local sizeof = ffi.sizeof
local copy = ffi.copy
local ffi_string = ffi.string
local cast = ffi.cast
local istype = ffi.istype
local metatype = ffi.metatype

local insert = table.insert

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

ffi.cdef [[struct NibsTuple { const uint8_t* first; const uint8_t* last; }]]
ffi.cdef [[struct NibsMap { const uint8_t* first; const uint8_t* last; }]]
ffi.cdef [[struct NibsArray { const uint8_t* first; const uint8_t* last; }]]
ffi.cdef [[struct NibsBinary { const uint8_t* first; const uint8_t* last; }]]
local StructNibsTuple = ffi.typeof 'struct NibsTuple'
local StructNibsMap = ffi.typeof 'struct NibsMap'
local StructNibsArray = ffi.typeof 'struct NibsArray'
local StructNibsBinary = ffi.typeof 'struct NibsBinary'

local Slice8 = ffi.typeof 'uint8_t[?]'
local Slice16 = ffi.typeof 'uint16_t[?]'
local Slice32 = ffi.typeof 'uint32_t[?]'
local Slice64 = ffi.typeof 'uint64_t[?]'

local U8Ptr = ffi.typeof 'uint8_t*'
local U16Ptr = ffi.typeof 'uint16_t*'
local U32Ptr = ffi.typeof 'uint32_t*'
local U64Ptr = ffi.typeof 'uint64_t*'

local U16Box = ffi.typeof 'uint16_t[1]'
local U32Box = ffi.typeof 'uint32_t[1]'
local U64Box = ffi.typeof 'uint64_t[1]'

-- Main types
local INT = 0
local FLOAT = 1
local SIMPLE = 2
local REF = 3
local TAG = 7
local BYTE = 8
local STRING = 9
local TUPLE = 10
local MAP = 11
local ARRAY = 12
-- Simple subtypes
local FALSE = 0
local TRUE = 1
local NULL = 2

local function is_integer(kind, val)
    if kind == "number" then
        return val % 1 == 0
    elseif kind == "cdata" then
        return istype(I64, val)
            or istype(I32, val)
            or istype(I16, val)
            or istype(I8, val)
            or istype(U64, val)
            or istype(U32, val)
            or istype(U16, val)
            or istype(U8, val)
    end
    return false
end

local function is_float(kind, val)
    if kind == "number" then
        return val % 1 ~= 0
    elseif kind == "cdata" then
        return istype(F64, val)
            or istype(F32, val)
    end
    return false
end

local converter = ffi.new 'union {double f;uint64_t i;}'
local function encode_float(val)
    converter.f = val
    return converter.i
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

---@param num integer
---@return integer
local function encode_zigzag(num)
    return num < 0 and num * -2 - 1 or num * 2
end

---@param ptr cdata
---@return integer
---@return integer
---@return integer
local function decode_pair(ptr)
    local head = ptr[0]
    local little = rshift(head, 4)
    local big = band(head, 0xf)
    if big == 0xc then
        return 2, little, ptr[1]
    elseif big == 0xd then
        return 3, little, cast(U16Ptr, ptr + 1)[0]
    elseif big == 0xe then
        return 5, little, cast(U32Ptr, ptr + 1)[0]
    elseif big == 0xf then
        return 9, little, cast(U64Ptr, ptr + 1)[0]
    else
        return 1, little, big
    end
end

local function skip(ptr)
    local offset, little, big = decode_pair(ptr)
    if little <= 5 then -- skip pair for small types
        return ptr + offset
    elseif little >= 8 then -- skip body for big types
        return ptr + offset + big
    elseif little == TAG then -- recurse for tags
        return skip(ptr + offset)
    else -- error for unknown types
        error('Unexpected nibs type: ' .. little)
    end
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

local function encode_pair(small, big)
    local pair = lshift(small, 4)
    if big < 0xc then
        return 1, tonumber(bor(pair, big))
    elseif big < 0x100 then
        return 2, { bor(pair, 12), tonumber(big) }
    elseif big < 0x10000 then
        return 3, { bor(pair, 13), U16Box { big } }
    elseif big < 0x100000000ULL then
        return 5, { bor(pair, 14), U32Box { big } }
    else
        return 9, { bor(pair, 15), U64Box { big } }
    end
end

local Nibs = {}

function Nibs.new()

    local refToId = {}
    local idToRef = {}

    --- Register a reference
    ---@param id integer
    ---@param ref any
    local function registerRef(id, ref)
        refToId[ref] = id
        idToRef[id] = ref
    end

    local tagEncoders = {}
    local tagDecoders = {}

    local function registerTag(id, encode, decode)
        tagEncoders[id] = encode
        tagDecoders[id] = decode
    end

    local NibsTuple = {}
    local NibsMap = {}
    local NibsArray = {}
    local NibsBinary = {}

    local decode

    local function decode_tag(ptr, id)
        local decoder = assert(tagDecoders[id], "missing decoder")
        local val, offset = decode(ptr)
        return decoder(val), offset
    end

    function decode(ptr)
        ptr = cast(U8Ptr, ptr)
        local offset, little, big = decode_pair(ptr)
        if little == INT then
            return decode_zigzag(big), offset
        elseif little == FLOAT then
            return decode_float(big), offset
        elseif little == SIMPLE then
            return decode_simple(big), offset
        elseif little == REF then
            return idToRef[big]
        elseif little == TAG then
            return decode_tag(ptr + offset, big)
        elseif little == BYTE then
            return NibsBinary.new(ptr + offset, big), offset + big
        elseif little == STRING then
            return ffi_string(ptr + offset, big), offset + big
        elseif little == TUPLE then
            return NibsTuple.new(ptr + offset, big), offset + big
        elseif little == MAP then
            return NibsMap.new(ptr + offset, big), offset + big
        elseif little == ARRAY then
            return NibsArray.new(ptr + offset, big), offset + big
        else
            error('Unexpected nibs type: ' .. little)
        end
    end

    function NibsTuple.new(ptr, len) return StructNibsTuple { ptr, ptr + len } end

    function NibsTuple:__len()
        local current = self.first
        local count = 0
        while current < self.last do
            current = skip(current)
            count = count + 1
        end
        return count
    end

    function NibsTuple:__index(index)
        local current = self.first
        while current < self.last do
            index = index - 1
            if index == 0 then return (decode(current)) end
            current = skip(current)
        end
    end

    function NibsTuple:__ipairs()
        return coroutine.wrap(function()
            local current = self.first
            local i = 1
            while current < self.last do
                local val, size = decode(current)
                current = current + size
                coroutine.yield(i, val)
                i = i + 1
            end
        end)
    end

    NibsTuple.__pairs = NibsTuple.__ipairs

    function NibsTuple:__tostring()
        local parts = {}
        for i, v in ipairs(self) do
            parts[i] = tostring(v)
        end
        return "(" .. table.concat(parts, ",") .. ")"
    end

    function NibsMap.new(ptr, len)
        return StructNibsMap { ptr, ptr + len }
    end

    function NibsMap.__len() return 0 end

    function NibsMap.__ipairs() return function() end end

    function NibsMap:__pairs()
        return coroutine.wrap(function()
            local current = self.first
            local last = self.last
            while current < last do
                local key, value, size
                key, size = decode(current)
                current = current + size
                if current >= last then break end
                value, size = decode(current)
                current = current + size
                coroutine.yield(key, value)
            end
        end)
    end

    function NibsMap:__index(index)
        local current = self.first
        local last = self.last
        while current < last do
            local key, size = decode(current)
            current = current + size
            if current >= last then return end

            if key == index then return (decode(current)) end
            current = skip(current)
        end
    end

    function NibsMap:__tostring()
        local parts = {}
        local i = 1
        for k, v in pairs(self) do
            parts[i] = tostring(k) .. ':' .. tostring(v)
            i = i + 1
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end

    function NibsArray.new(ptr, len) return StructNibsArray { ptr, ptr + len } end

    function NibsArray:__len()
        if self.first == self.last then return 0 end
        local _, _, count = decode_pair(self.first)
        return count
    end

    function NibsArray:__index(index)
        if self.first == self.last then return end
        local size, width, count = decode_pair(self.first)
        if index % 1 ~= 0 or index < 1 or index > count then return end
        local idx_first = self.first + size
        local idx_last = idx_first + width * count
        local ptr
        if size == 1 then
            ptr = cast(U8Ptr, idx_first + (index - 1) * width)
            if ptr + 1 > idx_last then return end
        elseif size == 2 then
            ptr = cast(U16Ptr, idx_first + (index - 1) * width)
            if ptr + 2 > idx_last then return end
        elseif size == 4 then
            ptr = cast(U32Ptr, idx_first + (index - 1) * width)
            if ptr + 2 > idx_last then return end
        elseif size == 8 then
            ptr = cast(U64Ptr, idx_first + (index - 1) * width)
            if ptr + 4 > idx_last then return end
        end
        local offset = ptr[0]
        return (decode(idx_last + offset))
    end

    function NibsArray:__ipairs()
        return coroutine.wrap(function()
            for i = 1, #self do
                coroutine.yield(i, self[i])
            end
        end)
    end

    NibsArray.__pairs = NibsArray.__ipairs

    function NibsArray:__tostring()
        local parts = {}
        for i, v in ipairs(self) do
            parts[i] = tostring(v)
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    function NibsBinary.new(ptr, len) return StructNibsBinary { ptr, ptr + len } end

    function NibsBinary:__len()
        return self.last - self.first
    end

    function NibsBinary:__index(index)
        local count = self.last - self.first
        if index % 1 == 0 and index >= 1 and index <= count then
            return cast(U8Ptr, self.first)[index + 1]
        end
    end

    function NibsBinary:__ipairs()
        return coroutine.wrap(function()
            local bytes = cast(U8Ptr, self.first)
            for i = 0, self.last - self.first - 1 do
                coroutine.yield(i + 1, bytes[i])
            end
        end)
    end

    NibsBinary.__pairs = NibsBinary.__ipairs

    function NibsBinary:__tostring()
        local parts = {}
        local bytes = cast(U8Ptr, self.first)
        for i = 0, self.last - self.first - 1 do
            parts[i] = tohex(bytes[i], 2)
        end
        return "<" .. table.concat(parts) .. ">"
    end

    local encode_any

    local function encode_tuple(tuple)
        local total = 0
        local body = {}
        for i, v in ipairs(tuple) do
            local size, entry = encode_any(v)
            body[i] = entry
            total = total + size
        end
        local size, head = encode_pair(TUPLE, total)
        return size + total, { head, body }
    end

    local function encode_array(array)
        local total = 0
        local body = {}
        local offsets = {}
        for i, v in ipairs(array) do
            local size, entry = encode_any(v)
            body[i] = entry
            offsets[i] = total
            total = total + size
        end
        local count = #offsets
        local index, width
        if count == 0 then
            return encode_pair(ARRAY, 0)
        end
        if total < 0x100 then
            width = 1
            index = Slice8(count, offsets)
        elseif total < 0x10000 then
            width = 2
            index = Slice16(count, offsets)
        elseif total < 0x100000000 then
            width = 4
            index = Slice32(count, offsets)
        else
            width = 8
            index = Slice64(count, offsets)
        end
        local more, head = encode_pair(width, count)
        total = more + sizeof(index) + total
        local size, prefix = encode_pair(ARRAY, total)
        return size + total, { prefix, head, index, body }
    end

    local function encode_map(map)
        local total = 0
        local body = {}
        for k, v in pairs(map) do
            local size, entry = encode_any(k)
            insert(body, entry)
            total = total + size
            size, entry = encode_any(v)
            insert(body, entry)
            total = total + size
        end
        local size, head = encode_pair(MAP, total)
        return size + total, { head, body }
    end

    local encode_base

    ---@param val any
    function encode_any(val)
        local refId = refToId[val]
        if refId then
            return encode_pair(REF, refId)
        end
        for i, encode in pairs(tagEncoders) do
            local encoded = encode(val)
            if encoded then
                local size1, head = encode_pair(TAG, i)
                local size2, data = encode_base(encoded)
                return size1 + size2, { head, data }
            end
        end
        return encode_base(val)
    end

    function encode_base(val)
        local kind = type(val)
        if is_integer(kind, val) then
            return encode_pair(INT, encode_zigzag(val))
        elseif is_float(kind, val) then
            return encode_pair(FLOAT, encode_float(val))
        elseif kind == 'boolean' then
            return encode_pair(SIMPLE, val and TRUE or FALSE)
        elseif kind == 'nil' then
            return encode_pair(SIMPLE, NULL)
        elseif kind == 'cdata' then
            if istype(StructNibsMap, val) then
                return encode_map(val)
            elseif istype(StructNibsTuple, val) then
                return encode_tuple(val)
            end
            local len = sizeof(val)
            local size, head = encode_pair(BYTE, len)
            return size + len, { head, val }
        elseif kind == 'string' then
            local len = #val
            local size, head = encode_pair(STRING, len)
            return size + len, { head, val }
        elseif kind == 'table' then
            local meta = getmetatable(val)
            if meta == OrderedList then
                return encode_array(val)
            elseif meta == OrderedMap then
                return encode_map(val)
            elseif is_array_like(val) then
                return encode_tuple(val)
            else
                return encode_map(val)
            end
        else
            error('Unsupported value type: ' .. kind)
        end
    end

    local function encode(val)
        local i = 0
        local size, data = encode_any(val)
        local buf = Slice8(size)
        local function write(d)
            local kind = type(d)
            if kind == 'number' then
                buf[i] = d
                i = i + 1
            elseif kind == 'cdata' then
                local len = sizeof(d)
                copy(buf + i, d, len)
                i = i + len
            elseif kind == 'string' then
                copy(buf + i, d)
                i = i + #d
            elseif kind == 'table' then
                for j = 1, #d do write(d[j]) end
            end
        end

        write(data)
        assert(size == i)
        return buf
    end

    metatype(StructNibsTuple, NibsTuple)
    metatype(StructNibsMap, NibsMap)
    metatype(StructNibsArray, NibsArray)
    metatype(StructNibsBinary, NibsBinary)

    --- Returns true if a value is a virtual nibs container.
    local function is(val)
        return istype(StructNibsTuple, val)
            or istype(StructNibsMap, val)
            or istype(StructNibsArray, val)
    end

    local function isMap(val)
        return istype(StructNibsMap, val)
    end

    local function isList(val)
        return istype(StructNibsTuple, val)
            or istype(StructNibsArray, val)
    end

    return {
        encode = encode,
        decode = decode,
        is = is,
        isMap = isMap,
        isList = isList,
        registerRef = registerRef,
        registerTag = registerTag,
    }

end

return Nibs

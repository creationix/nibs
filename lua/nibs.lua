--[[lit-meta
    name = "creationix/nibs"
    version = "1.0.1"
    homepage = "https://github.com/creationix/nibs"
    description = "An implementation of nibs serialization format for luajit."
    tags = {"nibs","serialization","jit"}
    license = "MIT"
    author = { name = "Tim Caswell" }
]]

local bit = require 'bit'
local rshift = bit.rshift
local band = bit.band
local lshift = bit.lshift
local bor = bit.bor

local ffi = require 'ffi'
local sizeof = ffi.sizeof
local copy = ffi.copy
local ffi_string = ffi.string
local cast = ffi.cast
local istype = ffi.istype
local metatype = ffi.metatype

ffi.cdef[[struct NibsList { const uint8_t* first; const uint8_t* last; }]]
ffi.cdef[[struct NibsMap { const uint8_t* first; const uint8_t* last; }]]

local Slice = ffi.typeof "uint8_t[?]"
local U8Ptr = ffi.typeof "uint8_t*"
local U16Ptr = ffi.typeof "uint16_t*"
local U32Ptr = ffi.typeof "uint32_t*"
local U64Ptr = ffi.typeof "uint64_t*"
local U16Box = ffi.typeof "uint16_t[1]"
local U32Box = ffi.typeof "uint32_t[1]"
local U64Box = ffi.typeof "uint64_t[1]"
local StructNibsList = ffi.typeof "struct NibsList"
local StructNibsMap = ffi.typeof "struct NibsMap"

local insert = table.insert

local NibsList = {}
local NibsMap = {}

local function decode_pair(ptr)
    local head = ptr[0]
    local little = rshift(head, 4)
    local big = band(head, 0xf)
    if big == 0xc then
        return 2, little, ptr[1]
    elseif big == 0xd then
        return 3, little, cast(U16Ptr,ptr+1)[0]
    elseif big == 0xe then
        return 5, little, cast(U32Ptr,ptr+1)[0]
    elseif big == 0xf then
        return 9, little, cast(U64Ptr,ptr+1)[0]
    else
        return 1, little, big
    end
end

local function decode(ptr)
    ptr = cast(U8Ptr, ptr)
    local offset, little, big = decode_pair(ptr)
    if little == 0 then
        return big, offset
    elseif little == 1 then
        return -big, offset
    elseif little == 2 then
        if big == 0 then
            return false, offset
        elseif big == 1 then
            return true, offset
        elseif big == 2 then
            return nil, offset
        else
            error("Unexpected nibs simple subtype: " .. big)
        end
    elseif little == 4 then
        local slice = Slice(big)
        copy(slice, ptr + offset, big)
        return slice, offset + big
    elseif little == 5 then
        return ffi_string(ptr + offset, big), offset + big
    elseif little == 6 then
        return NibsList.new(ptr + offset, big), offset + big
    elseif little == 7 then
        return NibsMap.new(ptr + offset, big), offset + big
    else
        error("Unexpected nibs type: " .. little)
    end
end

local function skip(ptr)
    local offset, little, big = decode_pair(ptr)
    if little <= 4 then
        return ptr + offset
    elseif little < 10 then
        return ptr + offset + big
    else
        error("Unexpected nibs type: " .. little)
    end
end

function NibsList.new(ptr, len)
    return StructNibsList {ptr, ptr + len}
end

function NibsList:__len()
    local current = self.first
    local count = 0
    while current < self.last do
        current = skip(current)
        count = count + 1
    end
    return count
end

function NibsList:__index(index)
    local current = self.first
    while current < self.last do
        index = index - 1
        if index == 0 then
            return decode(current)
        end
        current = skip(current)
    end
end

function NibsList:__ipairs()
    local current = self.first
    local i = 0
    return function ()
        if current < self.last then
            local val, size = decode(current)
            current = current + size
            i = i + 1
            return i, val
        end
    end
end

NibsList.__pairs = NibsList.__ipairs

function NibsMap.new(ptr, len)
    return setmetatable({ __nibs_ptr = ptr, __nibs_len = len }, NibsMap)
end

function NibsMap.__len()
    return 0
end

function NibsMap.__ipairs()
    return function () end
end

function NibsMap:__pairs()
    local current = self.__nibs_ptr
    local last = current + self.__nibs_len
    return function ()
        if current >= last then return end
        local key, value, size
        key, size = decode(current)
        current = current + size
        if current >= last then return end
        value, size = decode(current)
        current = current + size
        return key, value
    end
end

function NibsMap:__index(index)
    local current = self.__nibs_ptr
    local last = current + self.__nibs_len
    while current < last do
        local key, size = decode(current)
        current = current + size
        if current >= last then return end

        if key == index then
            return (decode(current))
        end
        current = skip(current)
    end
end

local function encode_pair(small, big)
    local pair = lshift(small, 4)
    if big < 0xc then
        return 1, bor(pair, big)
    elseif big < 0x100 then
        return 2, { bor(pair, 12), big }
    elseif big < 0x10000 then
        return 3, { bor(pair, 13), U16Box {big} }
    elseif big < 0x100000000 then
        return 5, { bor(pair, 14), U32Box {big} }
    else
        return 9, { bor(pair, 15), U64Box {big} }
    end
end

---@type table
---@return boolean
local function is_list(val)
    local i = 1
    for key in pairs(val) do
        if key ~= i then return false end
        i = i + 1
    end
    return true
end

local encode_any

local function encode_list(list)
    local total = 0
    local body = {}
    for i = 1, #list do
        local size, entry = encode_any(list[i])
        insert(body, entry)
        total = total + size
    end
    local size, head = encode_pair(6, total)
    return size + total, {head, body}
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
    local size, head = encode_pair(7, total)
    return size + total, {head, body}
end


---@param val any
function encode_any(val)
    local kind = type(val)
    if kind == "number" then
        if val >= 0 then
            return encode_pair(0, val)  -- Integer
        else
            return encode_pair(1, -val) -- Negative Integer
        end
    elseif kind == "boolean" then
        return encode_pair(2, val and 1 or 0) -- Simple true/false
    elseif kind == "nil" then
        return encode_pair(2, 2) -- Simple nil
    elseif kind == "cdata" then
        local len = sizeof(val)
        local size, head = encode_pair(4, len)
        return size + len, {head, val}
    elseif kind == "string" then
        local len = #val
        local size, head = encode_pair(5, len)
        return size + len, {head, val}
    elseif kind == "table" then
        if is_list(val) then
            return encode_list(val)
        else
            return encode_map(val)
        end
    else
        error("Unsupported value type: " .. kind)
    end
end

local function encode(val)
    local i = 0
    local size, data = encode_any(val)
    local buf = Slice(size)
    local function write(d)
        local kind = type(d)
        if kind == "number" then
            buf[i] = d
            i = i + 1
        elseif kind == "cdata" then
            local len = sizeof(d)
            copy(buf+i, d, len)
            i = i + len
        elseif kind == "string" then
            copy(buf+i,d)
            i = i + #d
        elseif kind == "table" then
            for j = 1, #d do
                write(d[j])
            end
        end
    end
    write(data)
    assert(size == i)
    return buf
end

metatype(StructNibsList, NibsList)
metatype(StructNibsMap, NibsMap)

--- Returns true if a value is a virtual nibs container.
local function is(val)
    return istype(StructNibsList, val)
        or istype(StructNibsMap, val)
end

return {
    encode = encode,
    decode = decode,
    is = is,
}
local bit = require 'bit'
local rshift = bit.rshift
local band = bit.band

local ffi = require 'ffi'
local cast = ffi.cast
local Slice = ffi.typeof "uint8_t[?]"
local U8Ptr = ffi.typeof "uint8_t*"
local U16Ptr = ffi.typeof "uint16_t*"
local U32Ptr = ffi.typeof "uint32_t*"
local U64Ptr = ffi.typeof "uint64_t*"

local NibsList = {}
local NibsMap = {}

local function decode_pair(ptr)
    ptr = cast(U8Ptr, ptr)
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
        ffi.copy(slice, ptr + offset, big)
        return slice, offset + big
    elseif little == 5 then
        return ffi.string(ptr + offset, big), offset + big
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
    return setmetatable({ __nibs_ptr = ptr, __nibs_len = len }, NibsList)
end

function NibsList:__len()
    local current = self.__nibs_ptr
    local last = current + self.__nibs_len
    local count = 0
    while current < last do
        current = skip(current)
        count = count + 1
    end
    return count
end

function NibsList:__index(index)
    local current = self.__nibs_ptr
    local last = current + self.__nibs_len
    while current < last do
        index = index - 1
        if index == 0 then
            return decode(current)
        end
        current = skip(current)
    end
end

function NibsList:__ipairs()
    local current = self.__nibs_ptr
    local last = current + self.__nibs_len
    local i = 0
    return function ()
        if current < last then
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

return decode
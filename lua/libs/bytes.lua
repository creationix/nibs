local ffi = require 'ffi'
local cast = ffi.cast
local new = ffi.new
local copy = ffi.copy
local string = ffi.string
local U8Ptr = ffi.typeof 'uint8_t*'
local Slice8 = ffi.typeof 'uint8_t[?]'
local min = math.min
local max = math.max


--- Interface for byte providers
---@alias ByteProvider fun(offset:number,length:number):string

--- Interface for LRU cache implementations
---@class SliceLRU
---@field get fun(offset:number,length:number):string?
---@field set fun(offset:number,length:number,value:string)

---@class Bytes
local Bytes = {}

---Turn a string into a memory backed byte provider
---@param data string
---@return ByteProvider
function Bytes.fromMemory(data)
    ---@param offset number
    ---@param length number
    return function(offset, length)
        return string.sub(data, offset + 1, offset + length)
    end
end

---Wrap a ByteProvider into one that aligns all reads on chunks.
---@param provider ByteProvider
---@param chunkSize number
---@return ByteProvider
function Bytes.makeChunked(provider, chunkSize)
    ---@param offset number
    ---@param length number
    return function(offset, length)
        local start = offset - (offset % chunkSize)
        local last = offset + length
        local result = new(Slice8, length)
        local ptr = cast(U8Ptr, result)
        while start < last do
            local slice = provider(start, chunkSize)
            local sptr = cast(U8Ptr, slice)
            local toffset = max(0, start - offset)
            local soffset = max(0, offset - start)
            local l = min(length - toffset, chunkSize - soffset)
            copy(ptr + toffset, sptr + soffset, l)
            start = start + chunkSize
        end
        return string(result, length)
    end
end

---Wrap a ByteProvider into one that caches repeat requests using an LRU
---@param provider ByteProvider
---@param lru SliceLRU
---@return ByteProvider
function Bytes.makeCached(provider, lru)
    return function(offset, length)
        local value = lru.get(offset, length)
        if not value then
            value = provider(offset, length)
            lru.set(offset, length, value)
        end
        return value
    end
end

return Bytes

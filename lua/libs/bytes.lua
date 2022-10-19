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
        local shift = offset % chunkSize
        local start = offset - shift
        local len = length + shift - 1
        len = len - (len % chunkSize) + chunkSize
        local slice = provider(start, len)
        return string.sub(slice, offset - start + 1, offset - start + length)
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

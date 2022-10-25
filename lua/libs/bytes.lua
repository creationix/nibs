local ffi = require 'ffi'
local cast = ffi.cast
local copy = ffi.copy
local ffi_string = ffi.string

local min = math.min
local max = math.max

local NibLib = require 'nib-lib'
local Slice8 = NibLib.U8Arr
local U8Ptr = NibLib.U8Ptr

--- Interface for byte providers
---@alias ByteProvider fun(offset:number,length:number):string

--- Interface for cache implementations
---@class ChunkCache
---@field get fun(offset:number):string?
---@field set fun(offset:number,value:string)

local Bytes = {}

---Wrap a ByteProvider into one that aligns all reads on chunks.
---@param provider ByteProvider
---@param chunkSize number
---@param cache ChunkCache?
---@return ByteProvider
function Bytes.makeChunked(provider, chunkSize, cache)

    ---@param offset number
    ---@param length number
    return function(offset, length)
        -- p(offset, length)
        local start = offset - (offset % chunkSize)
        local last = offset + length
        local result = Slice8(length)
        local ptr = cast(U8Ptr, result)
        while start < last do
            local slice = cache and cache.get(start)
            if not slice then
                slice = provider(start, chunkSize)
                if cache then
                    cache.set(start, slice)
                end
            end
            local sptr = cast(U8Ptr, slice)
            local toffset = max(0, start - offset)
            local soffset = max(0, offset - start)
            local l = min(length - toffset, #slice - soffset)
            copy(ptr + toffset, sptr + soffset, l)
            start = start + chunkSize
        end
        return ffi_string(result, length)
    end
end

return Bytes

local Http    = require 'coro-http'
local Bytes   = require 'bytes'
local PureLru = require 'lrucache-pureffi'
local Nibs    = require 'nibs'

local chunkSize = 1024 * 64 -- 64KiB
local maxCacheSize = 1024 * 1024 * 100 -- 100 MiB
local lru = assert(PureLru.new(maxCacheSize / chunkSize))

---@return ChunkCache
local function makeLRU(prefix)
    local function key(offset)
        local k = prefix .. '@' .. offset
        return k
    end

    return {
        ---@param offset number
        ---@return string?
        get = function(offset)
            return lru:get(key(offset))
        end,

        ---@param offset number
        ---@param value string
        set = function(offset, value)
            lru:set(key(offset), value)
        end
    }
end

---Create a byte provider from an HTTP url
---@param url string
---@return ByteProvider
local function fromHttpUrl(url)
    return function(offset, length)
        local range = string.format("bytes=%d-%d",
            offset, offset + length - 1)
        print(string.format("GET %s (Range: %s)", url, range))
        local res, body = Http.request("GET", url, { { "Range", range } })
        if res.code ~= 206 then
            error("unexpected response code " .. res.code)
        end
        return body
    end
end

return function(url)
    -- Make a caching chunked byte reader for reading this url
    local read = Bytes.makeChunked(fromHttpUrl(url), chunkSize, makeLRU(url .. '(' .. chunkSize .. ')'))
    -- Mount the remote as a nibs document and return it.
    return Nibs.get(read, 0)
end

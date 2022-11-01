local Http    = require 'coro-http'
local Bytes   = require 'bytes'
local PureLru = require 'lrucache-pureffi'
local Nibs    = require 'nibs'

-- local chunkSize = 1024 * 64 -- 64KiB
local chunkSize = 1024
local maxCacheSize = 1024 * 1024 * 100 -- 100 MiB
local lru = assert(PureLru.new(maxCacheSize / chunkSize))

--- Cache instance that acts like a plain table, but caches in the
--- shared lru instance using a local prefix.
---@class LRUCache
---@field prefix string
local Cache = {}

-- TODO: use strong etag as cache key somehow

---@param prefix string
---@return LRUCache
function Cache.new(prefix)
    return setmetatable({ prefix = prefix }, Cache)
end

---@param offset number
---@return string?
function Cache:__index(offset)
    return lru:get(self.prefix .. '@' .. offset)
end

---@param offset number
---@param value string
function Cache:__newindex(offset, value)
    lru:set(self.prefix .. '@' .. offset, value)
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
    local read = Bytes.makeChunked(fromHttpUrl(url), chunkSize, Cache.new(url .. '(' .. chunkSize .. ')'))
    -- Mount the remote as a nibs document and return it.
    return Nibs.get(read, 0)
end

local Bytes = require './bytes'

---Create a tiny LRU that holds a single value
---@return SliceLRU
local function singleLru()
    ---@type number
    local lastOffset
    ---@type number
    local lastLength
    ---@type string
    local lastValue
    return {
        get = function(offset, length)
            if offset == lastOffset and length == lastLength then
                return lastValue
            end
        end,
        set = function(offset, length, value)
            lastOffset = offset
            lastLength = length
            lastValue = value
        end,
    }
end

---Logs calls to provider with a callback
---@param provider ByteProvider
---@param input? fun(offset:number, length:number)
---@param output? fun(bytes:string)
---@return ByteProvider
local function logger(provider, label, input, output)
    ---@param offset number
    ---@param length number
    return function(offset, length)
        if input then input(offset, length) end
        print(string.format("%s <- %d/%d", label, offset, length))
        local result = provider(offset, length)
        print(string.format("%s -> %q", label, result))
        if output then output(result) end
        return result
    end
end

-- Setup a simple memory based bytes provider for testing
local b = Bytes.fromMemory "0123456789"

-- Log all calls to this provider for testing.
---@type number
local lastOffset
---@type number
local lastLength
---@type string
local lastResult
b = logger(b, "    memory", function(offset, length)
    lastOffset = offset
    lastLength = length
end, function(result)
    lastResult = result
end)

-- Test the basic memory interface
assert(b(0, 1) == "0")
assert(lastOffset == 0)
assert(lastLength == 1)
assert(lastResult == "0")
assert(b(0, 2) == "01")
assert(b(9, 1) == "9")
assert(b(5, 1) == "5")

-- Add in a cache layer with more logging
local c = Bytes.makeCached(b, singleLru())
c = logger(c, "  cached")

-- Verify the cache is working
lastOffset = -1
assert(c(0, 1) == "0")
assert(lastOffset == 0)
assert(lastLength == 1)
assert(lastResult == "0")

lastOffset = -1
assert(c(0, 1) == "0")
assert(lastOffset == -1)

lastOffset = -1
assert(c(0, 2) == "01")
assert(lastOffset == 0)

lastOffset = -1
assert(c(9, 1) == "9")
assert(lastOffset == 9)

lastOffset = -1
assert(c(5, 1) == "5")
assert(lastOffset == 5)

-- Add in a chunker to align reads to the memory provider with more logging
local d = Bytes.makeChunked(c, 5)
d = logger(d, "chunked")

-- Make sure the calls to the memory provider are the expected chunks
lastOffset = -1
assert(d(0, 1) == "0")
assert(lastOffset == 0)
assert(lastLength == 5)
assert(lastResult == "01234")

lastOffset = -1
assert(d(4, 1) == "4")
assert(lastOffset == -1)

lastOffset = -1
assert(d(4, 2) == "45")
assert(lastOffset == 0)
assert(lastLength == 10)
assert(lastResult == "0123456789")

lastOffset = -1
assert(d(5, 1) == "5")
assert(lastOffset == 5)
assert(lastLength == 5)
assert(lastResult == "56789")

lastOffset = -1
assert(d(5, 2) == "56")
assert(lastOffset == -1)

assert(d(0, 10) == "0123456789")

-- Test some edge cases
-- should each layer short circuit this? probably not since it shouldn't ever happen in real code
assert(d(0, 0) == "")

-- not sure if this is desired behavior, but it works.
assert(d(0, 20) == "0123456789")
assert(d(9, 10) == "9")
assert(d(10, 10) == "")

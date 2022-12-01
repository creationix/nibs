local Utils = require 'test-utils'
local Bytes = require 'bytes'

---Create a tiny LRU that holds a single value
---@return table<number,string>
local function singleLru()
    ---@type number
    local lastOffset
    ---@type string
    local lastValue

    local meta = {}

    ---@param offset number
    ---@return string?
    function meta:__index(offset)
        if offset == lastOffset then
            return lastValue
        end
    end

    ---@param offset number
    ---@param value string
    function meta:__newindex(offset, value)
        lastOffset = offset
        lastValue = value
    end

    return setmetatable({}, meta)
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
local b = Utils.fromMemory "0123456789"

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


-- Add in a chunker to align reads to the memory provider with more logging
local d = Bytes.makeChunked(b, 5, singleLru())
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
assert(lastOffset == 5)
assert(lastLength == 5)
assert(lastResult == "56789")

lastOffset = -1
assert(d(5, 1) == "5")
assert(lastOffset == -1)

lastOffset = -1
assert(d(5, 2) == "56")
assert(lastOffset == -1)

assert(d(0, 10) == "0123456789")

-- Test some edge cases
-- should each layer short circuit this? probably not since it shouldn't ever happen in real code
assert(d(0, 0) == "")

-- if you read off the end, it should be zero filled
assert(d(0, 20) == "0123456789\0\0\0\0\0\0\0\0\0\0")
assert(d(9, 10) == "9\0\0\0\0\0\0\0\0\0")
assert(d(10, 10) == "\0\0\0\0\0\0\0\0\0\0")

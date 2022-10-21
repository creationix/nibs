local ffi = require 'ffi'
local Slice8 = ffi.typeof 'uint8_t[?]'

local Trie = require 'trie'
local function buf(str)
    return Slice8(#str, str)
end

local y = 1
while y < 100000 do
    local size = math.floor(y + 0.5)
    y = y * 1.7782794100389228
    local sample = {}
    for i = 1, size do
        sample[buf('n' .. tostring(i))] = i
    end
    local seed, count, width, index = Trie.encode(sample)
    print(string.format("data-size=%d seed=%02x width=%d count=%d size=%d overhead=%.2f",
        size, seed, width, count, width * count, width * count / size
    ))
end

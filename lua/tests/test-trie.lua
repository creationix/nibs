local Utils = require 'test-utils'
local NibLib = require 'nib-lib'

local Trie = require 'trie'

local y = 1
collectgarbage("collect")
while y < 100000 do
    collectgarbage("collect")
    local size = math.floor(y + 0.5)
    y = y * 1.7782794100389228
    local sample = {}
    for i = 1, size do
        sample[NibLib.strToBuf('n' .. tostring(i))] = i
        -- sample[buf('x' .. tostring(i))] = i * 10
    end
    local count, width, index = Trie.encode(sample)
    print(string.format("data-size=%d width=%d count=%d size=%d overhead=%.2f",
        size, width, count, width * count, width * count / size
    ))
    index = NibLib.bufToStr(index)
    for k, v in pairs(sample) do
        local read = Utils.fromMemory(index)
        local o = Trie.walk(read, 0, count, width, k)
        if tonumber(o) ~= tonumber(v) then
            p(k, v, o)
            Utils.hex_dump(index)
            error "Mismatch"
        end
    end
end

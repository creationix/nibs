local PrettyPrint = require 'pretty-print'
local p = PrettyPrint.prettyPrint
local colorize = PrettyPrint.colorize

local Nibs  = require 'nibs2'
local Json  = require 'ordered-json'
local Utils = require 'nibs-utils'
local ffi   = require 'ffi'

local function hex_dump(buf)
    local parts = {}
    for i = 1, math.ceil(#buf / 16) * 16 do
        if (i - 1) % 16 == 0 then
            table.insert(parts, colorize("userdata", string.format('%08x  ', i - 1)))
        end
        table.insert(parts, i > #buf and '   ' or colorize('cdata', string.format('%02x ', buf:byte(i))))
        if i % 8 == 0 then
            table.insert(parts, ' ')
        end
        if i % 16 == 0 then
            table.insert(parts, colorize('braces', buf:sub(i - 16 + 1, i):gsub('%c', '.') .. '\n'))
        end
    end
    print(table.concat(parts))
end

local json = require('fs').readFileSync('test.json')
print("json " .. #json)
local test = assert(Json.decode(json))
-- p(test)
local encoded1 = Nibs.encode(test)
print("nibs " .. #encoded1)
-- hex_dump(encoded1)

print()
local dups = Utils.findDuplicates(test)
print(#dups .. " dups")
local reffed = Utils.addRefs(test, dups)
-- p(reffed)
local encoded2 = Nibs.encode(reffed)
-- hex_dump(encoded2)
print("nibs(reffed) " .. #encoded2)

print()
local idx = Utils.enableIndices(reffed, 32)
-- p(idx)
local encoded3 = Nibs.encode(idx)
-- hex_dump(encoded3)
print("nibs(reffed+indexed) " .. #encoded3)

-- p(reffed)

local inputs = {
    "[1,2,3,4]",
    '{"name":"Tim","age":40}',
}

for i, json in ipairs(inputs) do
    local v = Json.decode(json)
    p(v)
    local encoded1 = Nibs.encode(v)
    local dups = Utils.findDuplicates(v)
    p(dups)
    -- print(#dups .. " dups")
    local reffed = Utils.addRefs(v, dups)
    -- p(reffed)
    local encoded2 = Nibs.encode(reffed)

    print(string.format("% 3s(i) % 10s(J) % 10s(N) % 10s(d) % 10s(R)",
        i, #json, #encoded1, #dups, #encoded2))
end

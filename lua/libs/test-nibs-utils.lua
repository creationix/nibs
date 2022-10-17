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

local test = assert(Json.decode [=[
[
    { "color": "red", "fruits": ["apple", "strawberry"] },
    { "color": "green", "fruits": ["apple"] },
    { "color": "yellow", "fruits": ["apple", "banana"] }
]
]=])
p(test)
local encoded1 = Nibs.encode(test)
hex_dump(encoded1)

print()
local reffed = Utils.addRefs(test, Utils.findDuplicateStrings(test))
p(reffed)
local encoded2 = Nibs.encode(reffed)
hex_dump(encoded2)

print()
local idx = Utils.enableIndices(test, 3)
p(idx)
local encoded3 = Nibs.encode(idx)
hex_dump(encoded3)

local p = require('pretty-print').prettyPrint
local colorize = require('pretty-print').colorize
local Nibs = require "nibs2"

local tests = require('fs').readFileSync(module.dir .. "/nibs-tests.txt")
local Json = require 'ordered-json'

local tohex = bit.tohex
local byte = string.byte
local concat = table.concat

local function dump_string(str)
    local parts = {}
    for i = 1, #str do
        parts[i] = tohex(byte(str, i), 2)
    end
    return concat(parts)
end

local nibs = Nibs.new()

p(Nibs)
p(nibs)

collectgarbage("collect")
for line in string.gmatch(tests, "[^\n]+") do
    collectgarbage("collect")
    if line:sub(1, 4) == "self" then
        collectgarbage("collect")
        local code = "return function(self) " .. line .. " end"
        collectgarbage("collect")
        loadstring(code)()(nibs)
        collectgarbage("collect")
    else
        collectgarbage("collect")
        local text, hex = line:match " *([^|]+) +%| +(..+)"
        collectgarbage("collect")
        if not text then
            collectgarbage("collect")
            print("\n" .. colorize("highlight", "(| " .. line .. " |)") .. "\n")
        else
            collectgarbage("collect")
            local value = Json.decode(text) or loadstring(
                "local inf,nan,null=1/0,0/0\n" ..
                "return " .. text)()
            collectgarbage("collect")
            local expected = loadstring('return "' .. hex:gsub("..", function(h) return "\\x" .. h end) .. '"')()
            collectgarbage("collect")
            local actual = nibs:encode(value)
            p(value, dump_string(actual))

            collectgarbage("collect")
            if expected ~= actual then
                collectgarbage("collect")
                p(value, expected, actual)
                collectgarbage("collect")
                error(string.format("Encode mismatch for (%s | %s)", text, hex))
            end
            collectgarbage("collect")
        end
        collectgarbage("collect")
    end
    collectgarbage("collect")
end
collectgarbage("collect")

local found, refs = Nibs.find(function(val)
    local t = type(val)
    return t == "function"
        or t == "cdata"
        or (t == "string" and #val > 3)
        or (t == "number" and (val % 1 ~= 0 or val >= 32768 or val < -32768))
end, 1, _G)

nibs.index_limit = 0
local refs_encoded = nibs:encode(refs)

nibs.index_limit = 10
local encoded1 = nibs:encode(_G)

nibs.refs = refs
local encoded2 = refs_encoded .. nibs:encode(_G)

nibs.index_limit = 3200
local encoded3 = refs_encoded .. nibs:encode(_G)

-- nibs.index_limit = 0
-- local encoded3 = nibs:encode(_G)

print(#encoded1, #encoded2, #encoded3)
print(#refs_encoded)

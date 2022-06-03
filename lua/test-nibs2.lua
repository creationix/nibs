local p = require('pretty-print').prettyPrint
local colorize = require('pretty-print').colorize
local color = require('pretty-print').colorize
local Nibs = require "nibs2"
local readFileSync = require('fs').readFileSync

local tests = readFileSync(module.dir .. "/nibs-tests.txt")
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
            -- p(value, dump_string(actual))

            collectgarbage("collect")
            print(string.format("% 26s | %s",
                text,
                colorize(expected == actual and "success" or "failure", dump_string(actual))))
            -- if expected ~= actual then
            --     collectgarbage("collect")
            --     print(colorize("failure", "Encode mismatch") .. string.format(": expected %s | %s", text, hex))
            -- end
            collectgarbage("collect")
        end
        collectgarbage("collect")
    end
    collectgarbage("collect")
end
collectgarbage("collect")

print "Corgis energy JSON dataset:\n"
print "Loading ..."
local json = assert(readFileSync(
    module.dir .. "/../bench/corgis/website/datasets/json/health/health.json"
))
print("Loaded " .. #json .. " bytes.\n")
print "Parsing..."
local data = Json.decode(json)
print "Parsed.\n"

print("Scanning dataset for repeat values...")
local found, refs = Nibs.find(function(val)
    local t = type(val)
    return t == "function"
        or t == "cdata"
        or (t == "string" and #val > 3)
        or (t == "number" and (val % 1 ~= 0 or val >= 32768 or val < -32768))
end, 3, data)
-- p(found)


print("Encoding " .. #refs .. " refs...")
nibs.index_limit = 0
nibs.refs = {}
local refs_encoded = nibs:encode(refs)
print("Refs size " .. #refs_encoded .. "\n")

local encoded

print("Encoding data without refs and index limit of 16...")
nibs.index_limit = 16
nibs.refs = {}
encoded = nibs:encode(data)
print("encoded size " .. #encoded .. "\n")

print("Encoding data without refs and index limit of Infinity...")
nibs.index_limit = 1 / 0
nibs.refs = {}
encoded = nibs:encode(data)
print("encoded size " .. #encoded .. "\n")

print("Encoding data with refs and index limit of 0...")
nibs.index_limit = 0
nibs.refs = refs
encoded = refs_encoded .. nibs:encode(data)
print("encoded + refs size " .. (#encoded + #refs_encoded) .. "\n")


print("Encoding data with refs and index limit of 16...")
nibs.index_limit = 16
nibs.refs = refs
encoded = refs_encoded .. nibs:encode(data)
print("encoded + refs size " .. (#encoded + #refs_encoded) .. "\n")

print("Encoding data with refs and index limit of infinity...")
nibs.index_limit = 1 / 0
nibs.refs = refs
encoded = refs_encoded .. nibs:encode(data)
print("encoded + refs size " .. (#encoded + #refs_encoded) .. "\n")

-- nibs.index_limit = 3200
-- local encoded3 = refs_encoded .. nibs:encode(data)

-- -- nibs.index_limit = 0
-- -- local encoded3 = nibs:encode(_G)

-- print(#encoded1, #encoded2, #encoded3)
-- print(#refs_encoded)

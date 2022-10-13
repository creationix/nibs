local Bytes = require './bytes'
local NibsReader = require './nibs-reader'

local p = require('pretty-print').prettyPrint
local dump = require('pretty-print').dump
local colorize = require('pretty-print').colorize
local color = require('pretty-print').colorize
local readFileSync = require('fs').readFileSync

local tests = readFileSync(module.dir .. "/../nibs-tests.txt")
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

local function equal(a, b)
    if a == b then return true end
    if tostring(a) == tostring(b) then return true end
    return false
end

for line in string.gmatch(tests, "[^\n]+") do
    if line:match("^[a-z]") then
        local code = "return function(self) self." .. line .. " end"
        loadstring(code)()(NibsReader)
    else
        local text, hex = line:match " *([^|]+) +%| +(..+)"
        if not text then
            print("\n" .. colorize("highlight", line) .. "\n")
        else
            local expected = Json.decode(text) or assert(loadstring(
                "local inf,nan,null=1/0,0/0\n" ..
                "return " .. text))()
            local encoded = loadstring('return "' .. hex:gsub("..", function(h) return "\\x" .. h end) .. '"')()

            local provider = Bytes.fromMemory(encoded)
            local actual, offset = NibsReader.get(provider, 0)

            local same = equal(expected, actual)
            print(string.format("% 26s | %s, %s",
                hex,
                colorize(same and "success" or "failure", text),
                colorize(offset == #encoded and "success" or "failure", offset)
            ))
            if not same then
                collectgarbage("collect")
                print(colorize("failure", string.format("% 26s | %s",
                    "Error, not as expected",
                    colorize("error", dump(actual)))))
                -- return nil, "Encode Mismatch"
            end
        end
    end
end

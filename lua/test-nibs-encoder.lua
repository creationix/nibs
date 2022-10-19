local p = require('pretty-print').prettyPrint
local colorize = require('pretty-print').colorize
local Nibs = require "nibs"
local readFileSync = require('fs').readFileSync
local ffi = require 'ffi'
local I64 = ffi.typeof 'int64_t'

local tests = assert(readFileSync(module.dir .. "/../nibs-tests.txt"))
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

p(Nibs)

collectgarbage("collect")
local options = {}
for line in string.gmatch(tests, "[^\n]+") do
    collectgarbage("collect")
    if line:match("^[a-z]") then
        collectgarbage("collect")
        local code = "return function(self) self." .. line .. " end"
        collectgarbage("collect")
        loadstring(code)()(options)
        collectgarbage("collect")
    else
        collectgarbage("collect")
        local text, hex = line:match " *([^|]+) +%| +(..+)"
        collectgarbage("collect")
        if not text then
            collectgarbage("collect")
            print("\n" .. colorize("highlight", line) .. "\n")
        else
            collectgarbage("collect")
            local value
            if string.match(text, "^-?[0-9]+$") then
                local neg = false
                local big = I64(0)
                for i = 1, #text do
                    if string.sub(text, i, i) == "-" then
                        neg = true
                    else
                        big = big * 10 - (string.byte(text, i, i) - 48)
                    end
                end
                if not neg then big = -big end
                p(big)
                if I64(tonumber(big)) == big then
                    value = tonumber(big)
                else
                    value = big
                end
                p(value)
            else
                value = Json.decode(text) or loadstring(
                    "local inf,nan,null=1/0,0/0\n" ..
                    "return " .. text)()
            end
            collectgarbage("collect")
            local expected = loadstring('return "' .. hex:gsub("..", function(h) return "\\x" .. h end) .. '"')()
            collectgarbage("collect")
            local actual = Nibs.encode(value)
            -- p(value, dump_string(actual))

            collectgarbage("collect")
            print(string.format("% 26s | %s",
                text,
                colorize(expected == actual and "success" or "failure", dump_string(actual))))
            if expected ~= actual then
                collectgarbage("collect")
                print(colorize("failure", string.format("% 26s | %s",
                    "Error, not as expected",
                    colorize("success", dump_string(expected)))))
                return nil, "Encode Mismatch"
            end
            collectgarbage("collect")
        end
        collectgarbage("collect")
    end
    collectgarbage("collect")
end
collectgarbage("collect")

local NibLib = require 'nib-lib'

local colorize = require('pretty-print').colorize
local readFileSync = require('fs').readFileSync

local Nibs = require "nibs"
local Tibs = require 'tibs'

local tests = assert(readFileSync(module.dir .. "/../../nibs-tests.txt"))

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
            local value = Tibs.decode(text)
            collectgarbage("collect")
            local expected = NibLib.hexStrToStr(hex)
            collectgarbage("collect")
            local actual = Nibs.encode(value)
            collectgarbage("collect")
            print(string.format("% 40s → %s",
                text,
                colorize(expected == actual and "success" or "failure", NibLib.strToHexStr(actual))))
            if expected ~= actual then
                collectgarbage("collect")
                print(colorize("failure", string.format("% 26s | %s",
                    "Error, not as expected",
                    colorize("success", NibLib.strToHexStr(expected)))))
                return nil, "Encode Mismatch"
            end
            collectgarbage("collect")
        end
        collectgarbage("collect")
    end
    collectgarbage("collect")
end
collectgarbage("collect")

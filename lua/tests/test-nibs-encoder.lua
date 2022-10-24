local NibLib = require 'nib-lib'

local colorize = require('pretty-print').colorize
local readFileSync = require('fs').readFileSync

local Nibs = require "nibs"
local Tibs = require 'tibs'

local filename = module.dir .. "/encoder-fixtures.tibs"
local text = assert(readFileSync(filename))
local allTests = assert(Tibs.decode(text))

collectgarbage("collect")
for section, tests in pairs(allTests) do
    print("\n" .. colorize("highlight", section) .. "\n")
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

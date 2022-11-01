local Utils = require 'test-utils'
local Nibs = require "nibs"
local Tibs = require 'tibs'
local NibLib = require 'nib-lib'

local colorize = require('pretty-print').colorize
local readFileSync = require('fs').readFileSync

local filename = module.dir .. "/../../fixtures/encoder-fixtures.tibs"
local text = assert(readFileSync(filename))
local allTests = assert(Tibs.decode(text))

for _ = 1, 10 do -- Multiple runs to exercise GC more
    collectgarbage("collect")
    for section, tests in pairs(allTests) do
        print("\n" .. colorize("highlight", section) .. "\n")
        for i = 1, #tests, 2 do
            local input = tests[i]
            local expected = NibLib.bufToStr(tests[i + 1])
            local actual = Nibs.encode(input)

            print(string.format("% 40s → %s",
                Tibs.encode(input),
                colorize(expected == actual and "success" or "failure", NibLib.strToHexStr(actual))))
            if expected ~= actual then
                collectgarbage("collect")
                print(colorize("failure", string.format("% 40s | %s",
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

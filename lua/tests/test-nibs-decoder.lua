local Utils = require 'test-utils'

local NibLib = require 'nib-lib'
local Tibs = require 'tibs'
local Nibs = require 'nibs'

local colorize = require('pretty-print').colorize

local readFileSync = require('fs').readFileSync
local filename = module.dir .. "/../../fixtures/decoder-fixtures.tibs"
local text = assert(readFileSync(filename))
local allTests = assert(Tibs.decode(text))

for _ = 1, 10 do -- Multiple runs to exercise GC more
    collectgarbage("collect")
    for section, tests in pairs(allTests) do
        print("\n" .. colorize("highlight", section) .. "\n")
        for i = 1, #tests, 2 do
            local input = tests[i]
            local expected = tests[i + 1]
            collectgarbage("collect")

            -- Actual decoded value
            local actual = Nibs.decode(NibLib.bufToStr(input))
            collectgarbage("collect")

            -- Compare with expected value
            local same = Utils.equal(expected, actual)
            collectgarbage("collect")

            print(string.format("% 40s → %s",
                NibLib.bufToHexStr(input),
                colorize(same and "success" or "failure", Tibs.encode(actual))
            ))
            if not same then
                collectgarbage("collect")
                print(colorize("failure", string.format("% 40s | %s",
                    "Error, not as expected",
                    colorize("success", Tibs.encode(expected)))))
                return nil, "Encode Mismatch"
            end
        end
    end
end

local ffi = require 'ffi'
local sizeof = ffi.sizeof

local Utils = require 'test-utils'

local NibLib = require 'nib-lib'
local Tibs = require 'tibs'
local Nibs = require 'nibs'

local colorize = require('pretty-print').colorize

local readFileSync = require('fs').readFileSync
local filename = module.dir .. "/decoder-fixtures.tibs"
local text = assert(readFileSync(filename))
local allTests = assert(Tibs.decode(text))

for _ = 1, 10 do -- Multiple runs to exercise GC more
    collectgarbage("collect")
    for section, tests in pairs(allTests) do
        print("\n" .. colorize("highlight", section) .. "\n")
        for input, expected in pairs(tests) do
            collectgarbage("collect")

            -- Wrapped as byte provider for nibs reader
            local provider = Utils.fromMemory(input)
            collectgarbage("collect")

            -- Actual decoded value and offset
            local actual, offset = Nibs.get(provider, 0)
            collectgarbage("collect")

            -- Compare with expected value
            local same = Utils.equal(expected, actual)
            collectgarbage("collect")

            print(string.format("% 40s → %s, %s",
                NibLib.bufToHexStr(input),
                colorize(same and "success" or "failure", Tibs.encode(actual)),
                colorize(offset == sizeof(input) and "success" or "failure", offset)
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

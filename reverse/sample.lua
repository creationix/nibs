local p = require('pretty-print').prettyPrint
local ReverseNibs = require 'rnibs'
local StreamingJsonParse = require './json-parse'

local fruit_json = [[
  [
    { "color": "red",    "fruit": [ "apple", "strawberry" ] },
    { "color": "green",  "fruit": [ "apple" ] },
    { "color": "yellow", "fruit": [ "apple", "banana" ] },
    true, false, null,
    0, 1, 100, -100, 0.1, 1.1
  ]
]]

-- local index = 1
-- local len = #fruit_json
-- while index <= len do
--     local token, first, last = StreamingJsonParse.next(fruit_json, index)
--     if not token then return end
--     p("token", token, first, last, string.sub(fruit_json, first, last))
--     index = last + 1
-- end

p("start")
assert(ReverseNibs.convert(fruit_json, {
    -- Automatically find the duplicated strings `color`, `fruit`, and `apple`.
    dups = ReverseNibs.find_dups(fruit_json),
    -- Force index for the toplevel array for testing purposes
    indexLimit = 3,
    emit = function (chunk)
        p("chunk", chunk)
    end
}))
p("end")

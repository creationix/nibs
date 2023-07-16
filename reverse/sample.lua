local p = require('pretty-print').prettyPrint
local ReverseNibs = require 'rnibs'

local docs = [[
  [
    { "color": "red",    "fruit": [ "apple", "strawberry" ] },
    { "color": "green",  "fruit": [ "apple" ] },
    { "color": "yellow", "fruit": [ "apple", "banana" ] }
  ]

  [ true, false, null ]

  [ 0, 1, 100, -100, 0.1, 1.1 ]

  [
    <1234beef 5678dead 9abc1337 def00000>,
    [
      { "type": "static" },
      { "type": "lambda" },
      { "type": "static" },
      { "type": "lambda" }
    ]
  ]
]]

-- local StreamingJsonParse = require './json-parse'
-- local index = 1
-- local len = #fruit_json
-- while index <= len do
--     local token, first, last = StreamingJsonParse.next(fruit_json, index)
--     if not token then return end
--     p("token", token, first, last, string.sub(fruit_json, first, last))
--     index = last + 1
-- end

local len = #docs
local index = 1
while index and index <= len do
  local chunks = {}
  index = ReverseNibs.convert(docs, {
    index = index,
    -- Automatically find the duplicated strings `color`, `fruit`, and `apple`.
    dups = ReverseNibs.find_dups(docs, index),
    -- Force index for the toplevel array for testing purposes
    indexLimit = 3,
    emit = function(chunk)
      local hex = chunk:gsub(".", function(c) return string.format("%02x", c:byte()) end)
      local line = string.format("CHUNK: <%s>", hex)
      if chunk:find("^[\t\r\n -~]*$") then
        line = line .. string.format(" %q", chunk)
      end
      print(line)
      chunks[#chunks + 1] = chunk
      return #chunk
    end
  })
  p(table.concat(chunks, ''))
end

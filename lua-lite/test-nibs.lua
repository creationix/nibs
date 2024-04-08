local inspect = require 'inspect'
local remove_all_metatables = function(item, path)
  if path[#path] ~= inspect.METATABLE then return item end
end
local dump = function(item)
  return inspect(item, { process = remove_all_metatables })
end



local Tibs = require './tibs'
local f = assert(io.open('../fixtures/decoder-fixtures.tibs', 'r'))
local decoder_fixtures = Tibs.decode(assert(f:read '*a'))
f:close()

local Nibs = require './nibs'
print(dump(Nibs))
for name, tests in pairs(decoder_fixtures) do
  print(string.format("\n\n%s:", name))
  for i = 1, #tests, 2 do
    local input = tests[i]
    local expected = tests[i + 1]
    print(Tibs.encode(input) .. " -> " .. Tibs.encode(expected))
    Nibs.read_pair(input)
    -- local actual = Nibs.decode(input)
  end
end

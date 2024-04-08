local inspect = require 'inspect'
local remove_all_metatables = function(item, path)
  if path[#path] ~= inspect.METATABLE then return item end
end
local dump = function(item)
  return inspect(item, { process = remove_all_metatables })
end

local ffi = require 'ffi'
local cast = ffi.cast
local U8Ptr = ffi.typeof 'uint8_t*'

local Tibs = require './tibs'
local f = assert(io.open('../fixtures/decoder-fixtures.tibs', 'r'))
local decoder_fixtures = Tibs.decode(assert(f:read '*a'))
f:close()

local Nibs = require './nibs'

for name, tests in pairs(decoder_fixtures) do
  print(string.format("\n\027[38;5;45;48;5;236m%s\027[0m", name))
  for i = 1, #tests, 2 do
    local input = tests[i]
    local expected = Tibs.encode(tests[i + 1])
    local actual = Tibs.encode(Nibs.decode_string(input))
    if expected == actual then
      print(string.format("%s -> \027[38;5;120;48;5;22m%s\027[0m", Tibs.encode(input), expected))
    else
      print(string.format("%s -> \027[38;5;196m%s\027[0m (\027[38;5;120;48;5;22m%s\027[0m)",
        Tibs.encode(input), actual, expected))
    end
  end
end

local ffi = require 'ffi'
local ReverseNibs = require "./rnibs"

local tests = {
  [[
    [
      { "color": "red", "fruit": ["apple", "strawberry", "cherry"] },
      { "color": "green", "fruit": ["apple", "grape"] },
      { "color": "purple", "fruit": ["grape"] },
      { "color": "yellow", "fruit": ["apple", "banana"] }
    ]
  ]], { 'color', 'fruit', 'apple', 'grape' },
  '[100, 200, 300, 100, 200]', { 100, 200 },
}
for i = 1, #tests, 2 do
  local json_str = tests[i]
  local expected_dups = tests[i + 1]
  local len = #json_str
  local json = ffi.new('uint8_t[?]', len)
  ffi.copy(json, json_str, len)
  local dups = ReverseNibs.find_dups(json, 0, len)
  p{json, dups, expected_dups}
  assert(type(dups) == type(expected_dups))
  if dups then
    assert(#dups == #expected_dups)
    for i = 1, #dups do
      assert(dups[i] == expected_dups[i])
    end
  end
end

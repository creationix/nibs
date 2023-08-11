local ffi = require 'ffi'
local ReverseNibs = require "./rnibs"

local tests = {
  {[[
    [
      { "color": "red", "fruit": ["apple", "strawberry", "cherry"] },
      { "color": "green", "fruit": ["apple", "grape"] },
      { "color": "purple", "fruit": ["grape"] },
      { "color": "yellow", "fruit": ["apple", "banana"] }
    ]
  ]], { 'color', 'fruit', 'apple', 'grape' }},
  {'[100, 200, 300, 100, 200]', { 100, 200 }},
}
for i = 1, #tests do
  ---@type string, (string|integer)[]
  local json_str, expected_dups = unpack(tests[i])
  local len = #json_str
  local json = ffi.new('uint8_t[?]', len)
  ffi.copy(json, json_str, len)
  local dups = assert(ReverseNibs.find_dups(json, 0, len))
  print(string.format("json: %q, dups: [%s], expected_dups: [%s]",
    json_str,
    table.concat(dups, ','),
    table.concat(expected_dups, ',')
  ))
  assert(type(dups) == type(expected_dups))
  if dups then
    assert(#dups == #expected_dups)
    for j = 1, #dups do
      assert(dups[j] == expected_dups[j])
    end
  end
end

local ffi = require 'ffi'
local ReverseNibs = require './rnibs'

local tests = {
    '0', 0,
    '1', 1,
    '-1', -1,
    '123456789', 123456789,
    '1.0', 1.0,
    '2.0', 2.0,
    '-1.0', -1.0,
    '-2.0', -2.0,
    '0.1', 0.1,
    '0.01', 0.01,
    '1e2', 100,
    '1E2', 100,
    '1e+2', 100,
    '1E+2', 100,
    '100e-2', 1,
    '100e-4', 0.01,
    -- Ensure it also supports full range of I64
    '-9223372036854775807', -9223372036854775807LL,
    '9223372036854775807', 9223372036854775807LL,
    '-9223372036854775808', -9223372036854775808LL,
}

for i = 1, #tests, 2 do
  local input = tests[i]
  local expected = tests[i + 1]
  local len = #input

  local json = ffi.new("uint8_t[?]", len)
  ffi.copy(json, input, len)
  local output = ReverseNibs.parse_number(json, 0, len)
  print(input, output)

  if output ~= expected then
    print("expected", expected)
    print("actual", output)
    error("Mismatch")
  end
end

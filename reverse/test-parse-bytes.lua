local ffi = require 'ffi'
local ReverseNibs = require './rnibs'



local tests = {
    '<deadbeef>', "\xde\xad\xbe\xef",
    '< de ad be ef >', "\xde\xad\xbe\xef",
    '<dead beef>', "\xde\xad\xbe\xef",
    '<d e a\td\rb\ne e f>', "\xde\xad\xbe\xef",
    '<DEADBEEF>', "\xde\xad\xbe\xef",
    '< DE AD\rBE EF >', "\xde\xad\xbe\xef",
    '<DEAD\nBEEF>', "\xde\xad\xbe\xef",
    '<D E A D B E E F>', "\xde\xad\xbe\xef",
    '<>', "",
    '< >', "",
}

local function same(buf, len, str)
    if len ~= #str then return false end
    for i = 1, len do
        if buf[i - 1] ~= string.byte(str, i) then return false end
    end
    return true
end

for i = 1, #tests, 2 do
  local input = tests[i]
  local expected_str = tests[i + 1]
  local len = #input

  local json = ffi.new("uint8_t[?]", len)
  ffi.copy(json, input, len)
  local output, size = ReverseNibs.parse_bytes(json, 0, len)
  print(input, output, size)


  if not same(output, size, expected_str) then
    print("expected", expected_str)
    print("actual", ffi.string(output, size))
    error("Mismatch")
  end
end

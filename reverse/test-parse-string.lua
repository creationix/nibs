local ffi = require 'ffi'
local ReverseNibs = require './rnibs'

local tests = {
  '"Hello World"', "Hello World",
  '"Newline\\nEscape"', "Newline\nEscape",
  '"Newline\\n"', "Newline\n",
  '"\\nEscape"', "\nEscape",
  '"\\n"', "\n",
  '"\\r\\t"', "\r\t",
  '"\\b\\f"', "\b\f",
  '"\t\f\b"', "\t\f\b",
  '"\\""', '"',
  '"\\"', '�',
  '""', '',
  '"\\u0000"', '\0',
  '"Double \\"quote\\""', 'Double "quote"',
  '"\\\\/\\\\/"', '\\/\\/',
  -- Surrogate pairs with unicode escaping in upper case
  '"\\uD801\\uDC1D"', '𐐝',
  '"\\uD83D\\uDE80"', '🚀',
  -- Same in lower case
  '"\\ud801\\udc1d"', '𐐝',
  '"\\ud83d\\ude80"', '🚀',
  -- Half of surrogate pair with unicode escapes
  '"\\ud83d"', '�',
  '"\\ud83da"', '�a',
  '"𐐤𐐮𐐺𐑆"', "𐐤𐐮𐐺𐑆",
  -- native utf8 char
  '"\xf0\x9f\x9a\x80"', "🚀",
  -- native surrogate pair (should be normalized)
  '"\xd8\x3d\xde\x80"', "🚀",
  -- Broken unicode escape
  '"\\u123?"', '�?',
  '"\\u123"', '�',
  '"\\u12?"', '�?',
  '"\\u12"', '�',
  '"\\u1?"', '�?',
  '"\\u1"', '�',
  '"\\u?"', '�?',
  '"\\u"', '�',
  -- Mixed escaped and not escaped surrogate pair
  '"\xd8\x3d\\ude80"', "🚀",
  '"\\ud83d\xde\x80"', "🚀",
}

for i = 1, #tests, 2 do
  local input = tests[i]
  local expected = tests[i + 1]
  local len = #input

  local json = ffi.new("uint8_t[?]", len)
  ffi.copy(json, input, len)
  local output = ReverseNibs.parse_string(json, 0, len)
  print(string.format("input: %q, output: %q", input, output))

  if output ~= expected then
    print("expected", expected)
    print("actual", output)
    error("Mismatch")
  end
end

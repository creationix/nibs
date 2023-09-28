local p = require('pretty-print').prettyPrint
local Nibs = require '../nibs'
local Tibs = Nibs.Tibs

local tests = {
    { 1, 2, 3 }, '[1,2,3]',
    { 1, 2, more = 3 }, '{"1":1,"2":2,"more":3}',
    -9223372036854775807LL, '-9223372036854775807',
    9223372036854775807LL, '9223372036854775807',
    -9223372036854775808LL, '-9223372036854775808',
}

for i = 1, #tests, 2 do
    local input = tests[i]
    local expected = tests[i + 1]
    local actual = Tibs.encode_json(input)
    p(input, expected, actual)
    assert(expected == actual)
end

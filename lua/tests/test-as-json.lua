local p = require('pretty-print').prettyPrint
local dump = require('pretty-print').dump
local Nibs = require '../nibs'
local Tibs = Nibs.Tibs

local tests = {
    { { 1, 2, 3 },                            '[1,2,3]' },
    { { 1, 2, more = 3 },                     '{"1":1,"2":2,"more":3}' },
    { { { 1, 2, more = 3 } },                 '[{"1":1,"2":2,"more":3}]' },
    { assert(Tibs.decode '[null,<00>,null]'), '[null,"\\u0000",null]' },
    { -9223372036854775807LL,                 '-9223372036854775807' },
    { 9223372036854775807LL,                  '9223372036854775807' },
    { -9223372036854775808LL,                 '-9223372036854775808' },
    { { [true] = false },                     '{"true":false}' },
    { assert(Tibs.decode '[<012345>]'),       '["\\u0001#E"]' },
    { { [{}] = true },                        nil },
}

for _, test in ipairs(tests) do
    local input = test[1]
    local expected = test[2]
    local actual, err = Tibs.encode_json(input)
    p(input, expected, actual, err)
    if expected == nil then
        if err == nil then
            error(string.format("Expected error for input %s, got %s", dump(input), actual))
        end
    else
        if expected ~= actual then
            error(string.format("Expected %s, got %s", expected, actual))
        end
    end
end

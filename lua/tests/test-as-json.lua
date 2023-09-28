local p = require('pretty-print').prettyPrint
local dump = require('pretty-print').dump
local Nibs = require '../nibs'
local Tibs = Nibs.Tibs

local tests = {
    { { 1, 2, 3 },                                   '[1,2,3]' },
    { { 1, 2, more = 3 },                            '{"1":1,"2":2,"more":3}' },
    { { { 1, 2, more = 3 } },                        '[{"1":1,"2":2,"more":3}]' },
    { assert(Tibs.decode '[null,<00>,null]'),        '[null,"\\u0000",null]' },
    { -9223372036854775807LL,                        '-9223372036854775807' },
    { 9223372036854775807LL,                         '9223372036854775807' },
    { -9223372036854775808LL,                        '-9223372036854775808' },
    { { [true] = false },                            '{"true":false}' },
    { assert(Tibs.decode '[<012345>]'),              '["\\u0001#E"]' },
    { { [{}] = true },                               nil },
    { { print },                                     nil },
    { setmetatable({}, { __is_array_like = false }), '{}' },
    { setmetatable({}, { __is_array_like = true }),  '[]' },
    { {},                                            '{}' },
    { setmetatable({}, { -- virtual table that acts like an array when using __len and __index only
        __is_array_like = true,
        __index = function(_, k) return k end,
        __len = function() return 10 end,
    }), '[1,2,3,4,5,6,7,8,9,10]' },
    { setmetatable({}, { -- virtual table that acts like an array using __ipairs only
        __is_array_like = true,
        __ipairs = function()
            local i = 0
            return function()
                if i < 10 then
                    i = i + 1
                    return i, i
                end
            end
        end,
    }), '[1,2,3,4,5,6,7,8,9,10]' },
    { setmetatable({}, { -- virtual table that acts like an object using __pairs only
        __is_array_like = false,
        __pairs = function()
            local i = 0
            return function()
                if i < 5 then
                    i = i + 1
                    return i, i
                end
            end
        end,
    }), '{"1":1,"2":2,"3":3,"4":4,"5":5}' },
    { setmetatable({}, { -- virtual table that acts like an array using __pairs only
        __pairs = function()
            local i = 0
            return function()
                if i < 5 then
                    i = i + 1
                    return i, i
                end
            end
        end,
    }), '[1,2,3,4,5]' },
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

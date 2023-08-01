local ffi = require 'ffi'
local ReverseNibs = require './rnibs'

local tests = {
    ' 0 ', { { "number", 1, 2 } },
    '[1,2,3]', { 
        { "[", 0, 1 },
        { "number", 1, 2 },
        { ",", 2, 3 },
        { "number", 3, 4 },
        { ",", 4, 5 },
        { "number", 5, 6 },
        { "]", 6, 7 } 
    },
    '[ 1, 2, 3 ]', {
        { "[", 0, 1 },
        { "number", 2, 3 },
        { ",", 3, 4 },
        { "number", 5, 6 },
        { ",", 6, 7 },
        { "number", 8, 9 },
        { "]", 10, 11 }
    },
    [[
        { "name": "Nibs",
          "open-license": true
        }
    ]], {},
}

for i = 1, #tests, 2 do
    local json_str = tests[i]
    local len = #json_str
    local json = ffi.new('uint8_t[?]', len)
    ffi.copy(json, json_str, len)
    local offset = 0
    local limit = len
    p(json_str)
    for _, result in ipairs(tests[i + 1]) do
        assert(offset < limit)
        local t, o, l = ReverseNibs.next_json_token(json, offset, limit)
        assert(t and o and l)
        p({ offset, limit }, { t, o, l }, result, ffi.string(json, o, l-o))
        assert(t == result[1], "mismatched token in result")
        assert(o == result[2], "mismatched offset in result")
        assert(l == result[3], "mismatched limit in result")
        offset = l
    end
    local t, o, l = ReverseNibs.next_json_token(json, offset, limit)
    assert(not t and not o and not l)
end

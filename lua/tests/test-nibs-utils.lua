local TestUtils = require 'test-utils'
local hex_dump = TestUtils.hex_dump

local colorize = require('pretty-print').colorize

local Nibs = require 'nibs'
local Tibs = require 'tibs'

local inputs = Tibs.Map.new(unpack {
    "empty list", "[]",
    "empty map", "{}",
    "empty array", "[#]",
    "empty trie", "{#}",
    "mixed types", '[0,-10,100,true,false,null,<123456>,"Hello","123456"]',
    "repeated", '["1234","5678","1234",true,false,"5678","1234","5678","1234","5678"]',
    "number", '1234',
    "string", '"Hello"',
    "array", '[1,2,3,4]',
    "small-object", '{0:1,2:3,4:5}',
    "hamburgers", '[2011125487,"deadbeef"]',
    "counters", '[0,-1,1,-2,2,-3,"000102030405"]',
    "object", '{"name":"Tim","age":40,"color":"blue"}',
    "mixed", '[' ..
        '{"color":"red",   "fruits":["apple","strawberry"]},' ..
        '{"color":"green", "fruits":["apple"]},' ..
        '{"color":"yellow","fruits":["apple","banana"]}' ..
        ']',
    "wide trie", [[{
      0:-1,1:-2,2:-3,3:-4,4:-5,5:-6,6:-7,7:-8,8:-9,9:-10,10:-11,11:-12,12:-13,13:-14,14:-15,15:-16
    }]],
    "test", [[{
        "one":   { "name": "one",   "value": 1000, "beef": false },
        "two":   { "name": "Two",   "value": 2000, "dead": true },
        "three": { "name": "three", "value": 3000, "ffee": null },
        "four":  { "name": "Four",  "value": 2000 },
        "five":  { "name": "five",  "value": 1000 }
    }]],
})

local function autoIndex(val)
    return Nibs.autoIndex(val, 4)
end

local tests = Tibs.Map.new(unpack {
    "Input Json", {},
    "Original", { Tibs.decode },
    "Original -> Json", { Tibs.decode, Tibs.encode },
    "Original -> Json -> Lua", { Tibs.decode, Tibs.encode, Tibs.decode },
    "Original -> Json -> Lua -> Json", { Tibs.decode, Tibs.encode, Tibs.decode, Tibs.encode },
    "Original -> Json -> Lua -> Nibs", { Tibs.decode, Tibs.encode, Tibs.decode, Nibs.encode },
    "Original -> Nibs", { Tibs.decode, Nibs.encode },
    "Original -> Nibs -> Lua", { Tibs.decode, Nibs.encode, Nibs.decode },
    "Deduplicated", { Tibs.decode, Nibs.deduplicate },
    "Deduplicated -> Json", { Tibs.decode, Nibs.deduplicate, Tibs.encode },
    "Deduplicated -> Json -> Lua", { Tibs.decode, Nibs.deduplicate, Tibs.encode, Tibs.decode },
    "Deduplicated -> Nibs", { Tibs.decode, Nibs.deduplicate, Nibs.encode },
    "Deduplicated -> Nibs -> Lua", { Tibs.decode, Nibs.deduplicate, Nibs.encode, Nibs.decode },
    "Indexed", { Tibs.decode, autoIndex },
    "Indexed -> Json", { Tibs.decode, autoIndex, Tibs.encode },
    "Indexed -> Json -> Lua", { Tibs.decode, autoIndex, Tibs.encode, Tibs.decode },
    "Indexed -> Json -> Lua -> Json", { Tibs.decode, autoIndex, Tibs.encode, Tibs.decode, Tibs.encode },
    "Indexed -> Nibs", { Tibs.decode, autoIndex, Nibs.encode },
    "Indexed -> Nibs -> Lua", { Tibs.decode, autoIndex, Nibs.encode, Nibs.decode },
    "Deduped -> Indexed", { Tibs.decode, Nibs.deduplicate, autoIndex },
    "Indexed -> Deduped", { Tibs.decode, Nibs.deduplicate, autoIndex },
    "Deduped -> Indexed -> Json", { Tibs.decode, Nibs.deduplicate, autoIndex, Tibs.encode },
    "Indexed -> Deduped -> Json", { Tibs.decode, Nibs.deduplicate, autoIndex, Tibs.encode },
    "Deduped -> Indexed -> Json -> Lua", { Tibs.decode, Nibs.deduplicate, autoIndex, Tibs.encode, Tibs.decode },
    "Indexed -> Deduped -> Json -> Lua", { Tibs.decode, Nibs.deduplicate, autoIndex, Tibs.encode, Tibs.decode },
    "Deduped -> Indexed -> Nibs", { Tibs.decode, Nibs.deduplicate, autoIndex, Nibs.encode },
    "Indexed -> Deduped -> Nibs", { Tibs.decode, Nibs.deduplicate, autoIndex, Nibs.encode },
    "Deduped -> Indexed -> Nibs -> Lua", { Tibs.decode, Nibs.deduplicate, autoIndex, Nibs.encode, Nibs.decode },
    "Indexed -> Deduped -> Nibs -> Lua", { Tibs.decode, Nibs.deduplicate, autoIndex, Nibs.encode, Nibs.decode },
})

local matchers = {
    {
        "Original",
        "Original -> Json -> Lua",
        "Original -> Nibs -> Lua",
    },
    {
        "Original -> Json",
        "Original -> Json -> Lua -> Json",
    },
    {
        "Original -> Nibs",
        "Original -> Json -> Lua -> Nibs",
    },
    {
        "Deduped",
        "Deduped -> Json -> Lua",
        -- "Deduped -> Nibs -> Lua",
    },
    {
        "Deduped -> Json",
        "Deduped -> Json -> Lua -> Json",
    },
    {
        "Indexed",
        "Indexed -> Json -> Lua",
        -- "Indexed -> Nibs -> Lua",
    },
    {
        "Indexed -> Json",
        "Indexed -> Json -> Lua -> Json",
    },
}


local extra_space = ""
for name, json in pairs(inputs) do
    local outputs = {}
    local big = #json > 1000
    print("\n\n" .. colorize("highlight", name:upper()))
    for test, list in pairs(tests) do
        print(extra_space .. colorize("success", test))
        local value = json
        for _, step in ipairs(list) do
            if type(step) == "table" then
                local fn = step[1]
                local args = { unpack(step, 2) }
                step = function(val)
                    return fn(val, unpack(args))
                end
            end
            collectgarbage("collect")
            value = assert(step(value))
            collectgarbage("collect")
        end
        outputs[test] = value
        if type(value) == "string" then
            if big then
                print(string.format("%d bytes total\n", #value))
            else
                hex_dump(value)
            end
            extra_space = ""
        else
            if not big then
                p(value)
            end
            extra_space = "\n"
        end
    end
    for _, group in ipairs(matchers) do
        local first = group[1]
        local expected = outputs[first]
        for i = 2, #group do
            local other = group[i]
            local actual = outputs[other]
            if expected and actual and not TestUtils.equal(expected, actual) then
                print(string.format("Expected (%s):", first))
                p(expected)
                print(string.format("Actual (%s):", other))
                p(actual)
                error(name .. " Mismatch in expected same outputs")
            end
        end
    end
end

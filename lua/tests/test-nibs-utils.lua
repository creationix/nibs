local TestUtils = require 'test-utils'
local hex_dump = TestUtils.hex_dump

local colorize = require('pretty-print').colorize

local Nibs = require 'nibs'
local Tibs = require 'tibs'

local inputs = Tibs.Map.new(unpack {
    "empty list", "[]",
    "empty map", "{}",
    "empty array", "[#]",
    "mixed types", '[0,-10,100,true,false,null,<123456>,"Hello","123456"]',
    "repeated", '["1234","5678","1234",true,false,"5678","1234","5678","1234","5678"]',
    "number", '1234',
    "string", '"Hello"',
    "array", '[1,2,3,4]',
    "small-object", '{0:1,2:3,4:5}',
    "hamburgers", '[2011125487,"deadbeef"]',
    "counters", '[0,-1,1,-2,2,-3,"000102030405"]',
    "object", '{"name":"Tim","age":40,"color":"blue"}',
    "mixed", '[#' ..
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
    error "TODO: autoindex"
end

local tests = Tibs.Map.new(unpack {
    "Input Tibs", {},
    "Original", { Tibs.decode },
    "Original -> Tibs", { Tibs.decode, Tibs.encode },
    "Original -> Tibs -> Lua", { Tibs.decode, Tibs.encode, Tibs.decode },
    "Original -> Tibs -> Lua -> Tibs", { Tibs.decode, Tibs.encode, Tibs.decode, Tibs.encode },
    "Original -> Tibs -> Lua -> Nibs", { Tibs.decode, Tibs.encode, Tibs.decode, Nibs.encode },
    "Original -> Nibs", { Tibs.decode, Nibs.encode },
    "Original -> Nibs -> Lua", { Tibs.decode, Nibs.encode, Nibs.decode },
    -- "Deduplicated", { Tibs.decode, Nibs.deduplicate },
    -- "Deduplicated -> Tibs", { Tibs.decode, Nibs.deduplicate, Tibs.encode },
    -- "Deduplicated -> Tibs -> Lua", { Tibs.decode, Nibs.deduplicate, Tibs.encode, Tibs.decode },
    -- "Deduplicated -> Nibs", { Tibs.decode, Nibs.deduplicate, Nibs.encode },
    -- "Deduplicated -> Nibs -> Lua", { Tibs.decode, Nibs.deduplicate, Nibs.encode, Nibs.decode },
    -- "Indexed", { Tibs.decode, autoIndex },
    -- "Indexed -> Tibs", { Tibs.decode, autoIndex, Tibs.encode },
    -- "Indexed -> Tibs -> Lua", { Tibs.decode, autoIndex, Tibs.encode, Tibs.decode },
    -- "Indexed -> Tibs -> Lua -> Tibs", { Tibs.decode, autoIndex, Tibs.encode, Tibs.decode, Tibs.encode },
    -- "Indexed -> Nibs", { Tibs.decode, autoIndex, Nibs.encode },
    -- "Indexed -> Nibs -> Lua", { Tibs.decode, autoIndex, Nibs.encode, Nibs.decode },
    -- "Deduped -> Indexed", { Tibs.decode, Nibs.deduplicate, autoIndex },
    -- "Indexed -> Deduped", { Tibs.decode, Nibs.deduplicate, autoIndex },
    -- "Deduped -> Indexed -> Tibs", { Tibs.decode, Nibs.deduplicate, autoIndex, Tibs.encode },
    -- "Indexed -> Deduped -> Tibs", { Tibs.decode, Nibs.deduplicate, autoIndex, Tibs.encode },
    -- "Deduped -> Indexed -> Tibs -> Lua", { Tibs.decode, Nibs.deduplicate, autoIndex, Tibs.encode, Tibs.decode },
    -- "Indexed -> Deduped -> Tibs -> Lua", { Tibs.decode, Nibs.deduplicate, autoIndex, Tibs.encode, Tibs.decode },
    -- "Deduped -> Indexed -> Nibs", { Tibs.decode, Nibs.deduplicate, autoIndex, Nibs.encode },
    -- "Indexed -> Deduped -> Nibs", { Tibs.decode, Nibs.deduplicate, autoIndex, Nibs.encode },
    -- "Deduped -> Indexed -> Nibs -> Lua", { Tibs.decode, Nibs.deduplicate, autoIndex, Nibs.encode, Nibs.decode },
    -- "Indexed -> Deduped -> Nibs -> Lua", { Tibs.decode, Nibs.deduplicate, autoIndex, Nibs.encode, Nibs.decode },
})

local matchers = {
    {
        "Original",
        "Original -> Tibs -> Lua",
        "Original -> Nibs -> Lua",
    },
    {
        "Original -> Tibs",
        "Original -> Tibs -> Lua -> Tibs",
    },
    {
        "Original -> Nibs",
        "Original -> Tibs -> Lua -> Nibs",
    },
    -- {
    --     "Deduped",
    --     "Deduped -> Tibs -> Lua",
    --     -- "Deduped -> Nibs -> Lua",
    -- },
    -- {
    --     "Deduped -> Tibs",
    --     "Deduped -> Tibs -> Lua -> Tibs",
    -- },
    -- {
    --     "Indexed",
    --     "Indexed -> Tibs -> Lua",
    --     -- "Indexed -> Nibs -> Lua",
    -- },
    -- {
    --     "Indexed -> Tibs",
    --     "Indexed -> Tibs -> Lua -> Tibs",
    -- },
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
            p("step", step)
            collectgarbage("collect")
            p("before", value)
            value = assert(step(value))
            p("after", value)
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
                p("Expected", expected)
                print(string.format("Actual (%s):", other))
                p("Actual", actual)
                error(name .. " Mismatch in expected same outputs")
            end
        end
    end
end

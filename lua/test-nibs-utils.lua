local PrettyPrint = require 'pretty-print'
local p = PrettyPrint.prettyPrint
local colorize = PrettyPrint.colorize

local Nibs       = require 'nibs'
local Json       = require 'ordered-json'
local OrderedMap = require('ordered').Map

---print a colorful hexdump of a string
---@param buf string
local function hex_dump(buf)
    local parts = {}
    for i = 1, math.ceil(#buf / 16) * 16 do
        if (i - 1) % 16 == 0 then
            table.insert(parts, colorize("userdata", string.format('%08x  ', i - 1)))
        end
        table.insert(parts, i > #buf and '   ' or colorize('cdata', string.format('%02x ', buf:byte(i))))
        if i % 8 == 0 then
            table.insert(parts, ' ')
        end
        if i % 16 == 0 then
            table.insert(parts, colorize('braces', buf:sub(i - 16 + 1, i):gsub('%c', '.') .. '\n'))
        end
    end
    print(table.concat(parts))
end

local inputs = OrderedMap.new(unpack {
    -- "repeated", '["1234","5678","1234",true,false,"5678","1234","5678","1234","5678"]',
    -- "number", '1234',
    -- "string", '"Hello"',
    -- "array", '[1,2,3,4]',
    -- "small-object", '{0:1,2:3,4:5}',
    -- "hamburgers", '[2011125487,"deadbeef"]',
    -- "counters", '[0,-1,1,-2,2,-3,"000102030405"]',
    -- "object", '{"name":"Tim","age":40,"color":"blue"}',
    -- "mixed", '[' ..
    --     '{"color":"red",   "fruits":["apple","strawberry"]},' ..
    --     '{"color":"green", "fruits":["apple"]},' ..
    --     '{"color":"yellow","fruits":["apple","banana"]}' ..
    --     ']',
    -- "wide trie", [[{
    --   0:-1,1:-2,2:-3,3:-4,4:-5,5:-6,6:-7,7:-8,8:-9,9:-10,10:-11,11:-12,12:-13,13:-14,14:-15,15:-16
    -- }]],
    "test", [[{
        "one":   { "name": "one",   "value": 1000, "beef": false },
        "two":   { "name": "Two",   "value": 2000, "dead": true },
        "three": { "name": "three", "value": 3000, "ffee": null },
        "four":  { "name": "Four",  "value": 2000 },
        "five":  { "name": "five",  "value": 1000 }
    }]],
    -- "vercel json", require('fs').readFileSync('test.json'),
})

local function autoIndex(val)
    return Nibs.autoIndex(val, 4)
end

local tests = OrderedMap.new(unpack {
    -- "Input Json", {},
    -- "Original", { Json.decode },
    -- "Original -> Json", { Json.decode, Json.encode },
    -- "Original -> Json -> Lua", { Json.decode, Json.encode, Json.decode },
    -- "Original -> Json -> Lua -> Json", { Json.decode, Json.encode, Json.decode, Json.encode },
    -- "Original -> Json -> Lua -> Nibs", { Json.decode, Json.encode, Json.decode, Nibs.encode },
    -- "Original -> Nibs", { Json.decode, Nibs.encode },
    -- "Original -> Nibs -> Lua", { Json.decode, Nibs.encode, Nibs.decode },
    -- "Deduplicated", { Json.decode, Nibs.deduplicate },
    -- "Deduplicated -> Json", { Json.decode, Nibs.deduplicate, Json.encode },
    -- "Deduplicated -> Json -> Lua", { Json.decode, Nibs.deduplicate, Json.encode, Json.decode },
    -- "Deduplicated -> Nibs", { Json.decode, Nibs.deduplicate, Nibs.encode },
    -- "Deduplicated -> Nibs -> Lua", { Json.decode, Nibs.deduplicate, Nibs.encode, Nibs.decode },
    "Indexed", { Json.decode, autoIndex },
    -- "Indexed -> Json", { Json.decode, autoIndex, Json.encode },
    -- "Indexed -> Json -> Lua", { Json.decode, autoIndex, Json.encode, Json.decode },
    -- "Indexed -> Json -> Lua -> Json", { Json.decode, autoIndex, Json.encode, Json.decode, Json.encode },
    "Indexed -> Nibs", { Json.decode, autoIndex, Nibs.encode },
    "Indexed -> Nibs -> Lua", { Json.decode, autoIndex, Nibs.encode, Nibs.decode },
    -- "Deduped -> Indexed", { Json.decode, Nibs.deduplicate, autoIndex },
    -- "Indexed -> Deduped", { Json.decode, Nibs.deduplicate, autoIndex },
    -- "Deduped -> Indexed -> Json", { Json.decode, Nibs.deduplicate, autoIndex, Json.encode },
    -- "Indexed -> Deduped -> Json", { Json.decode, Nibs.deduplicate, autoIndex, Json.encode },
    -- "Deduped -> Indexed -> Json -> Lua", { Json.decode, Nibs.deduplicate, autoIndex, Json.encode, Json.decode },
    -- "Indexed -> Deduped -> Json -> Lua", { Json.decode, Nibs.deduplicate, autoIndex, Json.encode, Json.decode },
    -- "Deduped -> Indexed -> Nibs", { Json.decode, Nibs.deduplicate, autoIndex, Nibs.encode },
    -- "Indexed -> Deduped -> Nibs", { Json.decode, Nibs.deduplicate, autoIndex, Nibs.encode },
    -- "Deduped -> Indexed -> Nibs -> Lua", { Json.decode, Nibs.deduplicate, autoIndex, Nibs.encode, Nibs.decode },
    -- "Indexed -> Deduped -> Nibs -> Lua", { Json.decode, Nibs.deduplicate, autoIndex, Nibs.encode, Nibs.decode },
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

local function equal(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) == "table" then
        if #a ~= #b then return false end
        for k, v in pairs(a) do
            if not equal(b[k], v) then return false end
            assert(equal(a[k], v), "Internally inconsistent")
        end
        for k, v in pairs(b) do
            if not equal(a[k], v) then return false end
            assert(equal(b[k], v), "Internally inconsistent")
        end
        return true
    end
    p(a, b)
    error("TODO: compare type" .. type(a))
end

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
            value = assert(step(value))
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
            if other and actual and not equal(expected, actual) then
                print(string.format("Expected (%s):", first))
                p(expected)
                print(string.format("Actual (%s):", other))
                p(actual)
                error(name .. " Mismatch in expected same outputs")
            end
        end
    end
end

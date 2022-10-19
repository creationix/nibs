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
    -- "vercel", require('fs').readFileSync('test.json'),
    -- "array", '[1,2,3,4]',
    -- "small-object", '{0:1,2:3,4:5}',
    -- "object", '{"name":"Tim","age":40,"color":"blue"}',
    -- "mixed", '[' ..
    --     '{"color":"red",   "fruits":["apple","strawberry"]},' ..
    --     '{"color":"green", "fruits":["apple"]},' ..
    --     '{"color":"yellow","fruits":["apple","banana"]}' ..
    --     ']',
    "trie", [[{
      0:-1,1:-2,2:-3,3:-4,4:-5,5:-6,6:-7,7:-8,8:-9,9:-10,10:-11,11:-12,12:-13,13:-14,14:-15,15:-16
    }]],
    -- "test", [[{
    --     "one":   { "name": "one",   "value": 1000, "beef": false },
    --     "two":   { "name": "Two",   "value": 2000, "dead": true },
    --     "three": { "name": "three", "value": 3000, "ffee": null },
    --     "four":  { "name": "Four",  "value": 2000 },
    --     "five":  { "name": "five",  "value": 1000 }
    -- }]],
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
    -- "Original -> Nibs -> Lua -> Nibs", { Json.decode, Nibs.encode, Nibs.decode, Nibs.encode },
    -- "Original -> Nibs -> Lua -> Json", { Json.decode, Nibs.encode, Nibs.decode },
    -- "Deduplicated", { Json.decode, Nibs.deduplicate },
    -- "Deduplicated -> Json", { Json.decode, Nibs.deduplicate, Json.encode },
    -- "Deduplicated -> Json -> Lua", { Json.decode, Nibs.deduplicate, Json.encode, Json.decode },
    -- "Deduplicated -> Json -> Lua -> Json", { Json.decode, Nibs.deduplicate, Json.encode, Json.decode, Json.encode },
    -- "Deduplicated -> Json -> Lua -> Nibs", { Json.decode, Nibs.deduplicate, Json.encode, Json.decode, Nibs.encode },
    -- "Deduplicated -> Nibs", { Json.decode, Nibs.deduplicate, Nibs.encode },
    -- "Deduplicated -> Nibs -> Lua", { Json.decode, Nibs.deduplicate, Nibs.encode, Nibs.decode },
    -- "Deduplicated -> Nibs -> Lua -> Json", { Json.decode, Nibs.deduplicate, Nibs.encode, Nibs.decode, Json.encode },
    -- "Deduplicated -> Nibs -> Lua -> Nibs", { Json.decode, Nibs.deduplicate, Nibs.encode, Nibs.decode, Nibs.encode },

    "Indexed", { Json.decode, autoIndex },
    -- "Indexed -> Json", { Json.decode, autoIndex, Json.encode },
    "Indexed -> Nibs", { Json.decode, autoIndex, Nibs.encode },
    -- "Indexed -> Json -> Lua", { Json.decode, autoIndex, Json.encode, Json.decode },
    "Indexed -> Nibs -> Lua", { Json.decode, autoIndex, Nibs.encode, Nibs.decode },
    -- "Indexed -> Json -> Lua -> Json", { Json.decode, autoIndex, Json.encode, Json.decode, Json.encode },
    -- "Indexed -> Nibs -> Lua -> Json", { Json.decode, autoIndex, Nibs.encode, Nibs.decode, Json.encode },
    -- "Indexed -> Json -> Lua -> Nibs", { Json.decode, autoIndex, Json.encode, Json.decode, Nibs.encode },
    -- "Indexed -> Nibs -> Lua -> Nibs", { Json.decode, autoIndex, Nibs.encode, Nibs.decode, Nibs.encode },

    -- "Deduped -> Indexed", { Json.decode, Nibs.deduplicate, autoIndex },
    -- "Indexed -> Deduped", { Json.decode, Nibs.deduplicate, autoIndex },
    -- "Deduped -> Indexed -> Json", { Json.decode, Nibs.deduplicate, autoIndex, Json.encode },
    -- "Indexed -> Deduped -> Json", { Json.decode, Nibs.deduplicate, autoIndex, Json.encode },
    -- "Deduped -> Indexed -> Nibs", { Json.decode, Nibs.deduplicate, autoIndex, Nibs.encode },
    -- "Indexed -> Deduped -> Nibs", { Json.decode, Nibs.deduplicate, autoIndex, Nibs.encode },
})

local matchers = {
    {
        "Original -> Json",
        "Original -> Json -> Lua -> Json",
        "Original -> Nibs -> Lua -> Json",
    },
    {
        "Original -> Nibs",
        "Original -> Json -> Lua -> Nibs",
        "Original -> Nibs -> Lua -> Nibs",
    },
    {
        "Deduplicated -> Json",
        "Deduplicated -> Json -> Lua -> Json",
        "Deduplicated -> Nibs -> Lua -> Json",
    },
    {
        "Deduplicated -> Nibs",
        "Deduplicated -> Json -> Lua -> Nibs",
        "Deduplicated -> Nibs -> Lua -> Nibs",
    },
}

local extra_space = ""
for name, json in pairs(inputs) do
    print("\n\n" .. colorize("highlight", name:upper()))
    for test, list in pairs(tests) do
        print(extra_space .. colorize("success", test))
        local values = { json }
        for _, step in ipairs(list) do
            if type(step) == "table" then
                local fn = step[1]
                local args = { unpack(step, 2) }
                step = function(val)
                    return fn(val, unpack(args))
                end
            end
            values = { step(values[1]) }
        end
        if type(values[1]) == "string" then
            hex_dump(values[1])
            extra_space = ""
        else
            p(unpack(values))
            extra_space = "\n"
        end
    end
end
--     print("\n" .. colorize("success", "Json"))
--     hex_dump(json)

--     print(colorize("success", "Json -> Lua"))
--     local v = assert(Json.decode(json))
--     p(v)

--     print("\n" .. colorize("success", "Json -> Lua -> Nibs"))
--     local encoded1 = Nibs.encode(v)
--     require('fs').writeFileSync(string.format("test-%s.nibs", name), encoded1)
--     hex_dump(encoded1)

--     print(colorize("success", "Json -> Lua -> Json"))
--     local json1 = Json.encode(v)
--     hex_dump(json1)

--     print(colorize("success", "Json -> Lua -> Nibs -> Lua"))
--     local decoded1 = Nibs.decode(encoded1)
--     p(decoded1)

--     local encoded1b = Nibs.encode(decoded1)
--     print("\n" .. colorize(encoded1b == encoded1 and "success" or "failure", "Json -> Lua -> Nibs -> Lua -> Nibs"))
--     require('fs').writeFileSync(string.format("test-%s-b.nibs", name), encoded1b)
--     hex_dump(encoded1b)

--     print(colorize("success", "Json -> Lua -> Json -> Lua"))
--     local decoded1t = Json.decode(json1)
--     p(decoded1t)

--     local encoded1c = Nibs.encode(decoded1t)
--     print("\n" .. colorize(encoded1c == encoded1 and "success" or "failure", "Json -> Lua -> Json -> Nibs"))
--     require('fs').writeFileSync(string.format("test-%s-b.nibs", name), encoded1c)
--     hex_dump(encoded1c)

--     print(colorize("success", "Nibs Deduplicated"))
--     local reffed = Nibs.addRefs(v, Nibs.findDuplicates(v))
--     p(reffed)

--     print('\n' .. colorize("success", "Nibs Encoded"))
--     local encoded2 = Nibs.encode(reffed)
--     require('fs').writeFileSync(string.format("test-%s-reffed.nibs", name), encoded2)
--     hex_dump(encoded2)

--     print(colorize("success", "Nibs Text Encoded"))
--     hex_dump(Json.encode(reffed))

--     print(colorize("success", "Nibs Decoded"))
--     local decoded2 = Nibs.decode(encoded2)
--     p(decoded2)

--     print('\n' .. colorize("success", "Nibs Indexed"))
--     local indexed = Nibs.enableIndices(reffed, 2)
--     p(indexed)

-- end

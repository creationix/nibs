local p = require('pretty-print').prettyPrint
local uv = require 'uv'
local readFileSync = require('fs').readFileSync
local Nibs = require '../lua/nibs'
local JSON = require 'json'

local json = assert(readFileSync("data.json"))
local nibs = assert(readFileSync("data.nibs"))


local function bench(name, action, fn)
    local start = uv.hrtime()
    print(string.format("Running %s %s for 1 seconds...", name, action))
    local count = 0
    while (uv.hrtime() - start) < 1000000000 * 1 do
        fn(count)
        count = count + 1
    end
    local delta = (uv.hrtime() - start) / 1000000000
    p { count = count, delta = delta }
    local rps = count / delta
    print(name .. " " .. action .. "s per second: " .. tostring(rps))
    return rps
end

-- local function walk(data, i)
--     return {
--         City = data.weather[i + 1].Station.City,
--         State = data.weather[i + 1].Station.State,
--     }
-- end

for _ = 1, 5 do
    bench("nibs", "decode", function() Nibs.decode(nibs) end)
    -- local nibsData = Nibs.decode(nibs)
    -- bench("nibs", "walk", function(i) walk(nibsData, i % 100) end)
    bench("json", "parse", function() JSON.parse(json) end)
    local data = JSON.parse(json)
    bench("json", "encode", function() return JSON.stringify(data) end)
    bench("nibs", "encode", function() return Nibs.encode(data) end)
end

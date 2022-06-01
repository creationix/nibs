local fs         = require 'fs'
local pathJoin   = require('luvi').path.join
local ordered    = require 'ordered'
local ffi        = require 'ffi'
local OrderedMap = ordered.OrderedMap
local Json       = require 'ordered-json'
local Nibs       = require 'nibs'

-- Find all repeated strings in a table recursively and sort by most frequent
local function findStrings(...)
    local allStrings = {}
    local function find(val)
        local t = type(val)
        if (t == "string" and #val > 1)
            or (t == "number" and (val % 1 ~= 0 or val >= 32768 or val <= 32769)) then
            allStrings[val] = (allStrings[val] or 0) + 1
        elseif t == "table" then
            for k, v in pairs(val) do
                find(k)
                find(v)
            end
        end
    end

    local args = { ... }
    for i = 1, select("#", ...) do
        find(args[i])
    end

    local repeats = {}
    local keys = {}
    for k, v in pairs(allStrings) do
        if v > 3 then
            repeats[k] = v
            table.insert(keys, k)
        end
    end
    table.sort(keys, function(a, b)
        return repeats[a] > repeats[b]
    end)
    local result = OrderedMap.new()
    for _, k in ipairs(keys) do
        result[k] = repeats[k]
    end
    return result, keys
end

local sitesDir = pathJoin(os.getenv "HOME", "sites")
for _, site in ipairs(fs.readdirSync(sitesDir)) do
    local siteDir = pathJoin(sitesDir, site)
    p(siteDir)
    local deploymentJson = assert(fs.readFileSync(pathJoin(siteDir, "deployment.json")))
    local deployment = assert(Json.decode(deploymentJson))
    local routes = deployment.routes or {}
    local pathsJson = assert(fs.readFileSync(pathJoin(siteDir, "deployment_paths.json")))
    local paths = assert(Json.decode(pathsJson))
    local result, keys = findStrings(routes, paths)
    local nibs = Nibs.new()
    for i, v in ipairs(keys) do
        nibs.registerRef(i, v)
    end

    local doc = nibs:encode {
        refs = keys,
        routes = routes,
        paths = paths
    }

    p { #deploymentJson + #pathsJson, ffi.sizeof(doc) }
    fs.writeFileSync(pathJoin(siteDir, "routing.nibs"), ffi.string(doc, ffi.sizeof(doc)))
    p(nibs:decode(doc))
end

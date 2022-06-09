local fs         = require 'fs'
local pathJoin   = require('luvi').path.join
local ordered    = require 'ordered'
local ffi        = require 'ffi'
local OrderedMap = ordered.OrderedMap
local Json       = require 'ordered-json'
local Nibs       = require 'nibs2'

local function shouldRef(val)
    local t = type(val)
    return (t == "string" and #val > 2)
        or (t == "number" and (val % 1 ~= 0 or val >= 128 or val < -128))
end

---@param str string
---@return (string)[]
local function split_path(str)
    local i = 1
    local l = #str
    local t = {}

    while i <= l do

        local potential = {}

        -- Match hashes
        local h1, h2 = str:find("[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+", i)
        if h1 then
            if (h2 - h1 + 1) % 2 == 1 then h1 = h1 + 1 end
            table.insert(potential, { h1, h2, 2 })
        end

        -- Match other patterns
        local f = l
        for _, pattern in ipairs {
            "[^a-zA-Z]+",
            "[/.&=]?[a-zA-Z0-9_-]+",
            "[%^]?[/.&=]?%b()[+/?*]?[$]?",
            "[/.&=]?%b[]",
            "[/.&=]?%b{}",
            "[/.&=]?%b<>",
        } do
            local a, b = str:find(pattern, i)
            if a and ((b - a) > 4) then
                f = math.min(f, a - 1)
                table.insert(potential, { a, b, 1 })
            end
        end

        if #potential == 0 then
            table.insert(potential, { i, f })
        end

        assert(#potential > 0)

        table.sort(potential, function(a, b)
            local a1, a2, p1 = unpack(a)
            local b1, b2, p2 = unpack(b)
            -- if a is before b, then keep it first
            if a2 < b1 then return true end
            -- if b is before a, then swap them
            if b2 < a1 then return false end
            -- if they overlap, put the longer one first (multiply priority)
            local c1 = (a2 - a1) * p1
            local c2 = (b2 - b1) * p2
            if c1 == c2 then
                return a1 < b1
            else
                return c1 >= c2
            end
        end)

        local a, b = unpack(potential[1])
        if a > i then
            table.insert(t, str:sub(i, a - 1))
        end
        table.insert(t, str:sub(a, b))
        i = b + 1
    end
    return t
end

local CompoundString = {}

function CompoundString:__tostring()
    return table.concat(self)
end

local Ref = {}
function Ref.new(num)
    return setmetatable({ num }, Ref)
end

local function trim(val, refs)
    if refs[val] then return val end

    local t = type(val)
    if t == "string" then
        if #val < 4 then return val end
        local parts = split_path(val)
        if #parts == 1 and type(parts[1]) == "string" then
            return parts[1]
        else
            return setmetatable(parts, CompoundString)
        end
    elseif t == "table" then
        -- Strip our nils from OrderedMap instances
        if getmetatable(val) == OrderedMap then
            local n = OrderedMap.new()
            for k, v in pairs(val) do
                if v ~= nil then
                    n[trim(k, refs)] = trim(v, refs)
                end
            end
            return n
        end
        for k, v in pairs(val) do
            val[trim(k, refs)] = trim(v, refs)
        end
    end
    return val
end

local function findhexstrings(val)
    local t = type(val)
    if type(val) == "string" and #val % 2 == 0 then
        local buf = ffi.new("uint8_t[?]", #val)
        ffi.copy(buf, val, #val)
        return buf
    elseif t == "table" then
        local c = setmetatable({}, getmetatable(val))
        for k, v in pairs(val) do
            c[findhexstrings(k)] = findhexstrings(v)
        end
        return c
    end
    return val
end

local function findrefs(val, refs)
    if refs[val] then return Ref.new(refs[val]) end
    if type(val) == "table" then
        local c = setmetatable({}, getmetatable(val))
        for k, v in pairs(val) do
            c[findrefs(k, refs)] = findrefs(v, refs)
        end
        return c
    end
    return val
end

local function restorerefs(val, refs)
    if type(val) == "table" then
        if getmetatable(val) == Ref then return val[1] end
        local c = setmetatable({}, getmetatable(val))
        for k, v in pairs(val) do
            c[restorerefs(k, refs)] = restorerefs(v, refs)
        end
        return c
    end
    return val
end

local sitesDir = pathJoin(os.getenv "HOME", "sites")
local data = {}
local c = 0
for _, site in ipairs(fs.readdirSync(sitesDir)) do
    -- for _, site in ipairs {
    --     "vercel.com",
    --     "www.dailywire.com",
    --     "www.solsniper.xyz",
    --     "www.justsunnies.com.au",
    -- } do
    local ok, err = xpcall(function()
        local siteDir = pathJoin(sitesDir, site)
        p(siteDir)
        local deploymentJson = assert(fs.readFileSync(pathJoin(siteDir, "deployment.json")))
        local deployment = assert(Json.decode(deploymentJson))
        local routes = deployment.routes or {}
        local pathsJson = assert(fs.readFileSync(pathJoin(siteDir, "deployment_paths.json")))
        local paths = assert(Json.decode(pathsJson))

        -- Optimize It!

        -- Get list of common strings that we don't want to split up.
        local function findString(v)
            return type(v) == "string" and #v >= 10
        end

        local result = Nibs.find(findString, 4, routes, paths)

        trim(routes, result)
        -- p(routes)
        -- os.exit()

        -- -- Turn paths into tree
        -- local tree = {}
        -- local leaf = {}
        -- for _, path in ipairs(paths) do
        --     local node = tree
        --     local segments = split_path(path.path)
        --     local i = 1
        --     local l = #segments
        --     local segment
        --     while i <= l do
        --         segment = segments[i]
        --         if node[leaf] then
        --             local old = node[leaf]
        --             node[leaf] = nil
        --             node[split_path(old.path)[i]] = old
        --         elseif node[segment] then
        --             node = node[segment]
        --             i = i + 1
        --         else
        --             break
        --         end
        --     end
        --     node[leaf] = path.id
        -- end
        -- p(tree)
        -- os.exit()

        local m = {}
        for _, path in ipairs(paths) do
            m[path.id] = path
            OrderedMap.delete(path, "id")
            OrderedMap.delete(path, "path")
            OrderedMap.delete(path, "deploymentId")
            OrderedMap.delete(path, "projectId")
            OrderedMap.delete(path, "createdAt")
            OrderedMap.delete(path, "updatedAt")
        end
        paths = m

        trim(paths, result)

        local keys
        result, keys = Nibs.find(shouldRef, 2, routes, paths)

        local doc = { routes, paths }
        doc = findrefs(doc, result)
        doc = findhexstrings(doc)
        doc = restorerefs(doc, result)
        -- p(doc)
        -- os.exit()

        -- for k, v in pairs(result) do
        --     p(k, v)
        -- end
        print("REF COUNT", #keys)
        -- os.exit()

        local nibs = Nibs.new()
        nibs.refs = {}
        nibs.index_limit = 0
        nibs.trie_optimize = 0
        local encoded_refs = nibs:encode(keys)

        nibs.refs = keys
        nibs.index_limit = 320
        nibs.trie_optimize = 16
        local encoded_doc = nibs:encode {
            routes = routes,
            paths = paths
        }

        local old = #deploymentJson + #pathsJson
        local new = #encoded_refs + #encoded_doc
        local delta = old - new
        local percent = new / old * 100
        print(string.format(
            "old_size:% 10d new_size:% 10d savings: % 10d (%02.1f%%) site: %s",
            old, new, delta, percent, site
        ))
        fs.writeFileSync(pathJoin(siteDir, "routing.nibs"), encoded_doc)
        fs.writeFileSync(pathJoin(siteDir, "routing.nibs.refs"), encoded_refs)
        table.insert(data, { site = site, old = old, new = new, delta = delta, percent = percent })
        -- p(nibs:decode(doc))
        c = c + 1
    end, debug.traceback)
    if not ok then print(err) end
    -- if c >= 100 then break end
end

local function get_total(key)
    local t = 0
    for i = 1, #data do
        t = t + data[i][key]
    end
    return t
end

local function get_avg(key)
    local total = get_total(key)
    local count = #data
    local avg = total / count
    return avg, total, count
end

local function get_max(key)
    local m = -1 / 0
    for i = 1, #data do
        m = math.max(m, data[i][key])
    end
    return m
end

local function get_min(key)
    local m = 1 / 0
    for i = 1, #data do
        m = math.min(m, data[i][key])
    end
    return m
end

local function get_p(key, ...)
    local column = {}
    for i = 1, #data do
        column[i] = data[i][key]
    end
    table.sort(column)
    local results = {}
    for i = 1, select("#", ...) do
        local percent = select(i, ...)
        local i = math.max(1, math.min(#column, math.floor(#column * percent + 0.5)))
        table.insert(results, column[i])
    end
    return unpack(results)
end

local function get_stats(key)
    local p50, p75, p90, p95, p99 = get_p(key, .5, .75, .9, .95, .99)
    local min = get_min(key)
    local max = get_max(key)
    local avg, total, count = get_avg(key)
    return {
        min = min, max = max, avg = avg, total = total, count = count,
        p50 = p50, p75 = p75, p90 = p90, p95 = p95, p99 = p99,

    }
end

for k, v in pairs {
    old = get_stats "old",
    new = get_stats "new",
    delta = get_stats "delta",
    percent = get_stats "percent",
} do
    p(k, v)
end
p("overall", (get_avg "percent"))

p(Nibs.buckets)
-- 06/06/22 honeycomb
-- 24,919,364,008 total requests in last 7 days
-- 17,243,970,810 total requests from top 1000 sites
-- top 1000 sites count for 69.1% of all traffic
-- these range from 3,567,070 to 1,053,663,076 (dailywire) each

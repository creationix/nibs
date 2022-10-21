local p = require('pretty-print').prettyPrint
local Json = require 'ordered-json'
local fs = require 'coro-fs'
local Nibs = require 'nibs'
local luvi = require 'luvi'

local filename = process.env.HOME .. "/sites/vercel.com/deployment_paths.json"
p(filename)
local doc = assert(Json.decode(assert(fs.readFile(filename))))

local remove = {
    id = true,
    deploymentId = true,
    projectId = true,
    path = true,
}

local optimized = {}
for i = 1, #doc do
    local entry = doc[i]
    local sub = {}
    for k, v in pairs(entry) do
        if not remove[k] then
            sub[k] = v
        end
    end
    local parent = optimized
    local path = luvi.path.splitPath(entry.path)
    for _, segment in ipairs(path) do
        local next = parent[segment]
        if not next then
            next = {}
            parent[segment] = next
        end
        parent = next
    end
    parent[""] = sub
end

optimized = Nibs.autoIndex(Nibs.deduplicate(optimized), 10)

print "Writing test.nibs..."
fs.writeFile("test.nibs", Nibs.encode(optimized))

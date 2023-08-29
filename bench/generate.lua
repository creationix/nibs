local ffi = require 'ffi'
local fs = require 'coro-fs'
local Nibs = require "../lua/nibs"
local Tibs = Nibs.Tibs

print "Combining corgis datasets..."
local data = Nibs.Map.new()
for entry in fs.scandir('./corgis/website/datasets/json') do
    if entry.type == 'directory' then
        local name = entry.name
        print(name)
        local jsonpath = string.format("./corgis/website/datasets/json/%s/%s.json", name, name)
        local json = assert(fs.readFile(jsonpath))
        local value = Tibs.decode(json)
        data[name] = value
    end
end

print "Generating data.json"
local combined_json = Tibs.encode(data)
fs.writeFile("data.json", combined_json)

print "Finding dups..."
local dups = Nibs.Tibs.find_dups(combined_json)
print(string.format("Found %d dups!", #dups))
print "Encoding as nibs..."
local nibs = Nibs.encode(data, dups)
print "Writing data.nibs..."
fs.writeFile("data.nibs", ffi.string(nibs, ffi.sizeof(nibs)))

print "Done Generating."

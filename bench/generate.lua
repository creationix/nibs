local ffi = require 'ffi'
local fs = require 'coro-fs'
local Nibs = require "../lua/nibs"
local JSON = require 'json'

print "Combining corgis datasets..."
local data = {}
for entry in fs.scandir('./corgis/website/datasets/json') do
    if entry.type == 'directory' then
        local name = entry.name
        print(name)
        local jsonpath = string.format("./corgis/website/datasets/json/%s/%s.json", name, name)
        local json = fs.readFile(jsonpath)
        local value = JSON.parse(json)
        data[name] = value
    end
end

print "Generating data.json"
fs.writeFile("data.json", JSON.stringify(data))

print "Generating data.nibs"
local nibs = Nibs.encode(data)
fs.writeFile("data.nibs", ffi.string(nibs, ffi.sizeof(nibs)))

print "Done Generating."

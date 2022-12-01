#!/usr/bin/env luvit

local fs = require 'coro-fs'

local Nibs = require 'nibs'
local Tibs = require 'tibs'
print(arg)
local input_path = assert(process.argv[2], "Missing input path as first argument")
local output_path = assert(process.argv[3], "Missing output path as second argument")
print("\nLoading and parsing input file '" .. input_path .. "'...")
local input = assert(Tibs.decode(assert(fs.readFile(input_path))))
-- p(input)

print("Marking containers larger than 10 for indexing...")
input = Nibs.autoIndex(input, 10)
-- p(input)

print("Looking for duplicate values...")
local dups = Nibs.findDuplicates(input)

print("Turning " .. #dups .. " duplicates into refs and scopes...")
input = Nibs.addRefs(input, dups)

print(Tibs.encode(input))
-- print("Encoding to nibs text format...")
-- local text = assert(Json.encode(input))
-- print(text)

print("Encoding to nibs binary format...")
local nibs = assert(Nibs.encode(input))

print("Writing output file '" .. output_path .. "'...")
fs.writeFile(output_path, nibs)

local Nibs  = require 'nibs2'
local Json  = require 'ordered-json'
local Utils = require 'nibs-utils'
local ffi   = require 'ffi'

local test = assert(Json.decode [=[
[
    { "color": "red", "fruits": ["apple", "strawberry"] },
    { "color": "green", "fruits": ["apple"] },
    { "color": "yellow", "fruits": ["apple", "banana"] }
]
]=])
p(test)
local encoded1 = Nibs.encode(test)
p(encoded1)

print()

local reffed = Utils.addRefs(test, Utils.findDuplicateStrings(test))
p(reffed)

local encoded2 = Nibs.encode(reffed)
p(encoded2)
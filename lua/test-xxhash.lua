local ffi = require 'ffi'
local xxhash = require 'xxhash'
local xxh64 = xxhash.xxh64
local xxh32 = xxhash.xxh32
local p = require('pretty-print').prettyPrint

p(xxhash)

local str = "Hello World"
local c = ffi.new("const char*", str)
p(str, xxh32(c, #str, 0), xxh64(c, #str, 0))

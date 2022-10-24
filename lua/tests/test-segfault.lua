local ffi = require 'ffi'
local Slice8 = ffi.typeof 'uint8_t[?]'
local str = ""
collectgarbage "collect"

-- This is good
local buf2 = Slice8(#str)
ffi.copy(buf2, str, #str)
collectgarbage "collect"

-- This is bad!
local buf = Slice8(#str, str)
collectgarbage "collect"

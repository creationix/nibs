local NibLib = require 'nib-lib'

local FakeArray = { __is_array_like = true }
function FakeArray.new() return setmetatable({}, FakeArray) end

local FakeMap = { __is_array_like = false }
function FakeMap.new() return setmetatable({}, FakeMap) end

assert(NibLib.hexStrToStr "dead" == "\xde\xad")
assert(NibLib.strToHexStr "\xde\xad" == "dead")
assert(NibLib.hexBufToStr(NibLib.strToBuf "dead") == "\xde\xad")
assert(NibLib.bufToHexStr(NibLib.strToBuf "\xde\xad") == "dead")
assert(NibLib.bufToStr(NibLib.hexBufToBuf(NibLib.strToBuf "dead")) == "\xde\xad")
assert(NibLib.bufToStr(NibLib.bufToHexBuf(NibLib.strToBuf "\xde\xad")) == "dead")
assert(NibLib.bufToStr(NibLib.hexStrToBuf "dead") == "\xde\xad")
assert(NibLib.bufToStr(NibLib.strToHexBuf "\xde\xad") == "dead")
assert(NibLib.isArrayLike({ 1, 2, 3, 4 }))
assert(NibLib.isArrayLike({}))
assert(not NibLib.isArrayLike({ 1, 2, 3, 4, more = true }))
assert(NibLib.isArrayLike(FakeArray.new()))
assert(not NibLib.isArrayLike(FakeMap.new()))

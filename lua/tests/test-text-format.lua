require 'test-utils'

local readFileSync = require('fs').readFileSync
local Tibs = require 'tibs'

local filename = module.dir .. "/../../fixtures/tibs-fixtures.txt"
local text = assert(readFileSync(filename))


local i = 0
for t in text:gmatch("[^\n]+") do
    i = i + 1
    local decoded = Tibs.decode(t)
    local encoded = Tibs.encode(decoded)
    p(i, t, decoded, encoded)
    assert(encoded == t, "Mismatch")
end

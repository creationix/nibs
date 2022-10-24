local PrettyPrint = require 'pretty-print'
local p = PrettyPrint.prettyPrint

local Tibs = require 'tibs'

local tests = {
    '[1,2,3]',
    '(&1,2,3)',
    '[#1,2,3]',
    '[null,2,null]',
    '([&0,null],2,null)',
    '[#null,2,null]',
    '{1:2,3:4,5:null}',
    '{#1:2,3:4,5:null}',
    '<0123456789abcdef>',
}
for i, t in ipairs(tests) do
    local decoded = Tibs.decode(t)
    local encoded = Tibs.encode(decoded)
    p(i, t, decoded, encoded)
    assert(encoded == t, "Mismatch")
end

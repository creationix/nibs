local PrettyPrint = require 'pretty-print'
local p = PrettyPrint.prettyPrint

local Json = require 'ordered-json'
local tests = {
    '[1,2,3]',
    '(2,3,&1)',
    '[#1,2,3]',
    '[null,2,null]',
    '(2,null,[&0,null])',
    '[#null,2,null]',
    '{1:2,3:4,5:null}',
    '{#1:2,3:4,5:null}',
}
for i, t in ipairs(tests) do
    local decoded = Json.decode(t)
    local encoded = Json.encode(decoded)
    p(i, t, decoded, encoded)
    assert(encoded == t, "Mismatch")
end

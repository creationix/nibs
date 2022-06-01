local p = require('pretty-print').prettyPrint
local Nibs = require "nibs2"

local tests = require('fs').readFileSync "nibs-tests.txt"

local Json = require 'ordered-json'

local nibs = Nibs.new()

p(Nibs)
p(nibs)

for line in string.gmatch(tests, "[^\n]+") do
    if line:sub(1, 4) == "self" then
        local code = "return function(self) " .. line .. " end"
        loadstring(code)()(nibs)
    else
        local text, hex = line:match " *([^|]+) +%| +(..+)"
        if not text then
            print("\n## " .. line .. " ##\n")
        else
            local value = Json.decode(text) or loadstring(
                "local inf,nan,null=1/0,0/0\n" ..
                "return " .. text)()
            local expected = loadstring('return "' .. hex:gsub("..", function(h) return "\\x" .. h end) .. '"')()
            local actual = nibs:encode(value)
            if expected ~= actual then
                p(value, expected, actual)
                error(string.format("Encode mismatch for (%s | %s)", text, hex))
            end
        end
    end
end

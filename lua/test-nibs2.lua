local Nibs = require "nibs2"

local tests = require('fs').readFileSync "nibs-tests.txt"

local nibs = Nibs.new()
for line in string.gmatch(tests, "[^\n]+") do
    local text, hex = line:match " *([^|]+) +%| +(..+)"
    if not text then
        print(line)
    else
        local value = loadstring("return " .. text)()
        local expected = loadstring('return "' .. hex:gsub("..", function(h) return "\\x" .. h end) .. '"')()
        local actual = nibs:encode(value)
        if expected ~= actual then
            p(value, expected, actual)
            error(string.format("Encode mismatch for (%s | %s)", text, hex))
        end
    end
end

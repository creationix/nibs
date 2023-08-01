-- Run this file with luvit to test
local ReverseNibs = require './rnibs'

local fs = require 'fs'

-- local dir = "test-docs"
-- for entry, type in fs.scandirSync(dir) do
--   local e = entry:find('%.json$')
--   if e and type == "file" then
--     local filename = dir .. '/' .. entry
--     local json = assert(fs.readFileSync(filename))
--     print(string.format("\nReading %d bytes from %s...", #json, filename))
--     local chunks = {}
--     ReverseNibs.convert(json, {
--       -- Automatically find the duplicated strings `color`, `fruit`, and `apple`.
--       dups = ReverseNibs.find_dups(json),
--       -- Force index for the toplevel array for testing purposes
--       indexLimit = 3,
--       emit = function(chunk)
--         local hex = chunk:gsub(".", function(c) return string.format("%02x", c:byte()) end)
--         local line = string.format("CHUNK: <%s>", hex)
--         if chunk:find("^[\t\r\n -~]*$") then
--           line = line .. string.format(" %q", chunk)
--         end
--         print(line)
--         chunks[#chunks + 1] = chunk
--         return #chunk
--       end
--     })
--     filename = dir .. '/' .. entry:sub(1,e) .. 'rnibs'
--     local data = table.concat(chunks, '')
--     print(string.format("Writing %d bytes to %s...", #data, filename))
--     fs.writeFileSync(filename, data)
--   end
-- end

local ffi = require 'ffi'
p(ReverseNibs)
local json_bytes, len
do
    local json_string = [[
        [
            "Hello",
            "Escape\nIt",
            "\"\'\\",
            "\r\t",
            "105\u00b0",
            "\uD801\uDC1D",
            "\uD83D\uDE80",
            "\ud801\udc1d",
            "\ud83d\ude80",
            "\ud83d",
            "\ud83da",
            "𐐤𐐮𐐺𐑆",
            "🚀"
        ]
    ]]
    json_string = '"\xd8\x3d\xde\x80"'
    -- {"name":"R-Nibs"},
    -- <deadbeef>, &1, &2
-- local json_string = "[ 0, -1, 1, true, false ]"
    len = #json_string
    ---@type integer[]
    json_bytes = ffi.new('uint8_t[?]', len)
    ffi.copy(json_bytes, json_string, len)
end

-- Verify we can still get to the bytes after the string is collected
collectgarbage "collect"
collectgarbage "collect"

local offset = 0
while true do
    local token, start, size = ReverseNibs.next_json_token(json_bytes, offset, len)
    if not token then break end
    p(token, start, size, ffi.string(json_bytes + start, size))

    offset = start + size
end

p(ReverseNibs.convert(json_bytes, len))

-- local _, data = ReverseNibs.convert([[
--     [
--         -9223372036854775807,
--         9223372036854775807,
--         -9223372036854775808
--     ]
-- ]], { indexLimit = 20 })
-- p{data=data}
-- local n = ReverseNibs.decode(data)
-- p(n)

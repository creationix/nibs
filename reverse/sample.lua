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

local _, data = ReverseNibs.convert('[7]', { indexLimit = 2 })
p{data=data}
local n = ReverseNibs.decode(data)
p "DUMP"
for key,val in next, n do
    print(key, ":", val)
end
p(n[1])
-- p(n)
-- for i = 1, #n do
--   p(i, n[i])
-- end

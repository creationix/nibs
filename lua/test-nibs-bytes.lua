local Json       = require 'json'
local p          = require('pretty-print').prettyPrint
local remoteNibs = require 'remote-nibs'
local fs         = require 'coro-fs'

-----------------------------
-- Make sure to run
-- python3 -m RangeHTTPServer
-----------------------------


local function walk(val)
    if type(val) == "table" then
        local mt = getmetatable(val)
        if mt.__is_array_like and mt.__is_indexed then
            p { "length" }
            local len = #val
            local n = math.random(1, len)
            p { "index", n }
            walk(val[n])
            p { "after", n }
        else
            local c = math.random(3, 5)
            p { "pairs" }
            for k, v in pairs(val) do
                p { "before index", k }
                walk(v)
                p { "after index", k }
                c = c - 1
                if c < 1 then break end
                p { "next pair" }
            end
        end
    end
end

local url = 'http://localhost:8000/solana.com.deployment_paths.reffed.indexed.nibs'
print("\n\n" .. url)
local doc = remoteNibs(url, 1024 * 16)

-- p(doc[100000000])

walk(doc)

--[[
in a repl do:
> doc = require('remote-nibs')('http://localhost:8000/solana.com.deployment_paths.reffed.indexed.nibs', 1024)

have fun!

]]

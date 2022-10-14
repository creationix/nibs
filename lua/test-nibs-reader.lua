local Bytes = require './bytes'
local NibsReader = require './nibs-reader'
local ffi = require 'ffi'
local I64 = ffi.typeof 'int64_t'

local p = require('pretty-print').prettyPrint
local dump = require('pretty-print').dump
local colorize = require('pretty-print').colorize
local color = require('pretty-print').colorize

local function dumper(val)
    if type(val) == "cdata" and ffi.typeof(val) ~= I64 then
        local b = ffi.cast("uint8_t*", val)
        local parts = { "<" }
        for i = 0, ffi.sizeof(val) - 1 do
            if i > 0 then parts[#parts + 1] = " " end
            parts[#parts + 1] = bit.tohex(b[i], 2)
        end
        parts[#parts + 1] = ">"
        return table.concat(parts)
    end
    if type(val) == "table" then return tostring(val) end
    return dump(val)
end

local readFileSync = require('fs').readFileSync

local tests = readFileSync(module.dir .. "/../nibs-tests.txt")
local Json = require 'ordered-json'

local tohex = bit.tohex
local byte = string.byte
local concat = table.concat

local function dump_string(str)
    local parts = {}
    for i = 1, #str do
        parts[i] = tohex(byte(str, i), 2)
    end
    return concat(parts)
end

local function equal(a, b)
    if a == b then return true end
    if tostring(a) == tostring(b) then return true end
    if type(a) ~= type(b) then return false end
    if type(a) == "number" or type(b) == "number" then
        if tostring(I64(a)) == tostring(I64(b)) then return true end
    end
    if type(a) == "cdata" then
        local len = ffi.sizeof(a)
        if len ~= ffi.sizeof(b) then return false end
        a = ffi.cast("uint8_t*", a)
        b = ffi.cast("uint8_t*", b)
        for i = 0, len - 1 do
            if a[i] ~= b[i] then return false end
        end
        return true
    end
    if type(a) == "table" then
        if #a ~= #b then return false end
        for k, v in pairs(a) do
            if not equal(v, b[k]) then return false end
            if not equal(v, a[k]) then
                p { "mismatch", k, v, a[k] }
                -- error "mismatch"
            end
        end
        for k, v in pairs(b) do
            if not equal(v, a[k]) then return false end
            if not equal(v, b[k]) then
                p { "mismatch", k, v, b[k] }
                error "mismatch"
            end
        end
        return true
    end
    return false
end

for line in string.gmatch(tests, "[^\n]+") do
    if line:match("^[a-z]") then
        local code = "return function(self) self." .. line .. " end"
        loadstring(code)()(NibsReader)
    else
        local text, hex = line:match " *([^|]+) +%| +(..+)"
        if not text then
            print("\n" .. colorize("highlight", line) .. "\n")
        else
            local expected
            if string.match(text, "^-?[0-9]+$") then
                local neg = false
                local big = I64(0)
                for i = 1, #text do
                    if string.sub(text, i, i) == "-" then
                        neg = true
                    else
                        big = big * 10 - (string.byte(text, i, i) - 48)
                    end
                end
                if not neg then big = -big end
                if I64(tonumber(big)) == big then
                    expected = tonumber(big)
                else
                    expected = big
                end
            else
                expected = Json.decode(text) or assert(loadstring(
                    "local inf,nan,null=1/0,0/0\n" ..
                    "return " .. text))()
            end
            local encoded = loadstring('return "' .. hex:gsub("..", function(h) return "\\x" .. h end) .. '"')()

            local provider = Bytes.fromMemory(encoded)
            local actual, offset = NibsReader.get(provider, 0)

            local same = equal(expected, actual)
            print(string.format("% 26s | %s, %s",
                hex,
                colorize(same and "success" or "failure", dumper(actual)),
                colorize(offset == #encoded and "success" or "failure", offset)
            ))
            if not same then
                collectgarbage("collect")
                print(colorize("failure", string.format("% 26s | %s",
                    "Error, not as expected",
                    colorize("success", dump(expected)))))
                return nil, "Encode Mismatch"
            end
        end
    end
end

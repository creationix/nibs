local PrettyPrint = require 'pretty-print'
local p = PrettyPrint.prettyPrint
local colorize = PrettyPrint.colorize

local ffi = require 'ffi'
local Slice8 = ffi.typeof 'uint8_t[?]'
local Bytes = require 'bytes'

local Trie = require 'trie'
local function buf(str)
    return Slice8(#str, str)
end

---print a colorful hexdump of a string
---@param buf string
local function hex_dump(buf)
    local parts = {}
    for i = 1, math.ceil(#buf / 16) * 16 do
        if (i - 1) % 16 == 0 then
            table.insert(parts, colorize("userdata", string.format('%08x  ', i - 1)))
        end
        table.insert(parts, i > #buf and '   ' or colorize('cdata', string.format('%02x ', buf:byte(i))))
        if i % 8 == 0 then
            table.insert(parts, ' ')
        end
        if i % 16 == 0 then
            table.insert(parts, colorize('braces', buf:sub(i - 16 + 1, i):gsub('%c', '.') .. '\n'))
        end
    end
    print(table.concat(parts))
end

local y = 1
while y < 100000 do
    local size = math.floor(y + 0.5)
    y = y * 1.7782794100389228
    local sample = {}
    for i = 1, size do
        sample[buf('n' .. tostring(i))] = i
    end
    local count, width, index = Trie.encode(sample)
    print(string.format("data-size=%d width=%d count=%d size=%d overhead=%.2f",
        size, width, count, width * count, width * count / size
    ))
    index = ffi.string(index, ffi.sizeof(index))
    for k, v in pairs(sample) do
        local read = Bytes.fromMemory(index)
        local o = Trie.walk(read, 0, count, width, k)
        if tonumber(o) ~= tonumber(v) then
            hex_dump(index)
            p(k, v, o)
            error "Mismatch"
        end
    end
end

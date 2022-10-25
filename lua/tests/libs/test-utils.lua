local ffi = require 'ffi'
local sizeof = ffi.sizeof
local ffi_string = ffi.string
local cast = ffi.cast

local min = math.min

local PrettyPrint = require 'pretty-print'
local colorize = PrettyPrint.colorize

_G.p = PrettyPrint.prettyPrint

local NibLib = require 'nib-lib'
local U8Ptr = NibLib.U8Ptr

local TestUtils = {}

---Turn a string into a memory backed byte provider
---@param data string|ffi.cdata*
---@return ByteProvider
function TestUtils.fromMemory(data)
    local typ = type(data)
    if typ == "string" then
        ---@param offset number
        ---@param length number
        return function(offset, length)
            return string.sub(data, offset + 1, offset + length)
        end
    elseif typ == "cdata" then
        local ptr = cast(U8Ptr, data)
        local len = sizeof(data)
        return function(offset, length)
            return ffi_string(ptr + offset, min(length, len - offset))
        end
    else
        error("Unsupported type " .. typ)
    end
end

---print a colorful hexdump of a string
---@param buf string
function TestUtils.hex_dump(buf)
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

local function equal(a, b)
    if a == b then return true end
    if tostring(a) == tostring(b) then return true end
    if type(a) ~= type(b) then return false end
    if type(a) == "cdata" then
        local len = sizeof(a)
        if len ~= sizeof(b) then return false end
        a = cast(U8Ptr, a)
        b = cast(U8Ptr, b)
        for i = 0, len - 1 do
            if a[i] ~= b[i] then return false end
        end
        return true
    end
    if type(a) == "table" then
        local mta = getmetatable(a) or {}
        local mtb = getmetatable(b) or {}
        if mta.__is_array_like ~= mtb.__is_array_like then return false end
        if mta.__is_indexed ~= mtb.__is_indexed then return false end
        if mta.__is_array_like then
            if #a ~= #b then return false end
            for k, v in ipairs(a) do
                if not equal(v, b[k]) then return false end
                if not equal(v, a[k]) then
                    p { "internal mismatch", k, v, a[k] }
                    error "internal mismatch"
                end
            end
            for k, v in ipairs(b) do
                if not equal(v, a[k]) then return false end
                if not equal(v, b[k]) then
                    p { "internal mismatch", k, v, b[k] }
                    error "internal mismatch"
                end
            end
            for i = 1, #a do
                if not equal(a[i], b[i]) then return false end
            end
        else
            for k, v in pairs(a) do
                if not equal(v, b[k]) then return false end
                if not equal(v, a[k]) then
                    p { "internal mismatch", k, v, a[k] }
                    error "internal mismatch"
                end
            end
            for k, v in pairs(b) do
                if not equal(v, a[k]) then return false end
                if not equal(v, b[k]) then
                    p { "internal mismatch", k, v, b[k] }
                    error "internal mismatch"
                end
            end
        end
        return true
    end
    return false
end

TestUtils.equal = equal

return TestUtils

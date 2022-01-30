local bit = require 'bit'
local lshift = bit.lshift
local bor = bit.bor

local insert = table.insert

local ffi = require 'ffi'
local sizeof = ffi.sizeof
local copy = ffi.copy
local Slice = ffi.typeof "uint8_t[?]"
local U16Box = ffi.typeof "uint16_t[1]"
local U32Box = ffi.typeof "uint32_t[1]"
local U64Box = ffi.typeof "uint64_t[1]"

local function encode_pair(small, big)
    local pair = lshift(small, 4)
    if big < 0xc then
        return 1, bor(pair, big)
    elseif big < 0x100 then
        return 2, { bor(pair, 12), big }
    elseif big < 0x10000 then
        return 3, { bor(pair, 13), U16Box {big} }
    elseif big < 0x100000000 then
        return 5, { bor(pair, 14), U32Box {big} }
    else
        return 9, { bor(pair, 15), U64Box {big} }
    end
end

---@type table
---@return boolean
local function is_list(val)
    local i = 1
    for key in pairs(val) do
        if key ~= i then return false end
        i = i + 1
    end
    return true
end

local encode_any

local function encode_list(list)
    local total = 0
    local body = {}
    for i = 1, #list do
        local size, entry = encode_any(list[i])
        insert(body, entry)
        total = total + size
    end
    local size, head = encode_pair(6, total)
    return size + total, {head, body}
end

local function encode_map(map)
    local total = 0
    local body = {}
    for k, v in pairs(map) do
        local size, entry = encode_any(k)
        insert(body, entry)
        total = total + size
        size, entry = encode_any(v)
        insert(body, entry)
        total = total + size
    end
    local size, head = encode_pair(7, total)
    return size + total, {head, body}
end


---@param val any
function encode_any(val)
    local kind = type(val)
    if kind == "number" then
        if val >= 0 then
            return encode_pair(0, val)  -- Integer
        else
            return encode_pair(1, -val) -- Negative Integer
        end
    elseif kind == "boolean" then
        return encode_pair(2, val and 1 or 0) -- Simple true/false
    elseif kind == "nil" then
        return encode_pair(2, 2) -- Simple nil
    elseif kind == "cdata" then
        local len = sizeof(val)
        local size, head = encode_pair(4, len)
        return size + len, {head, val}
    elseif kind == "string" then
        local len = #val
        local size, head = encode_pair(5, len)
        return size + len, {head, val}
    elseif kind == "table" then
        if is_list(val) then
            return encode_list(val)
        else
            return encode_map(val)
        end
    else
        error("Unsupported value type: " .. kind)
    end
end

local function encode(val)
    local i = 0
    local size, data = encode_any(val)
    local buf = Slice(size)
    local function write(d)
        local kind = type(d)
        if kind == "number" then
            buf[i] = d
            i = i + 1
        elseif kind == "cdata" then
            local len = sizeof(d)
            copy(buf+i, d, len)
            i = i + len
        elseif kind == "string" then
            copy(buf+i,d)
            i = i + #d
        elseif kind == "table" then
            for j = 1, #d do
                write(d[j])
            end
        end
    end
    write(data)
    assert(size == i)
    return buf
end

return encode
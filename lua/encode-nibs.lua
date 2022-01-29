local bit = require 'bit'
local lshift = bit.lshift
local rshift = bit.rshift
local bor = bit.bor
local band = bit.band

local insert = table.insert

local ffi = require 'ffi'
local Buffer = ffi.typeof "uint8_t[?]"
local sizeof = ffi.sizeof
local copy = ffi.copy

local Nibs = { Buffer = Buffer }

local function encode_pair(small, big)
    local pair = lshift(small, 4)
    if big < 0xc then
        return 1, bor(pair, big)
    elseif big < 0x100 then
        return 2, {bor(pair, 12), big}
    elseif big < 0x10000 then
        return 3, {bor(pair, 13),
            band(big,0xff), rshift(big, 8)}
    elseif big < 0x100000000 then
        return 5, {bor(pair, 14),
            band(big,0xff), band(rshift(big, 8),0xff),
            band(rshift(big, 16),0xff), rshift(big, 24)}
    else
        return 9, {bor(pair, 15),
            band(big,0xff),
            band(rshift(big, 8),0xff),
            band(rshift(big, 16),0xff),
            band(rshift(big, 24),0xff),
            band(rshift(big, 32),0xff),
            band(rshift(big, 40),0xff),
            band(rshift(big, 48),0xff),
            rshift(big, 56)}
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

function Nibs.encode_list(list)
    local total = 0
    local body = {}
    for i = 1, #list do
        local size, entry = Nibs.encode_any(list[i])
        insert(body, entry)
        total = total + size
    end
    local size, head = encode_pair(6, total)
    return size + total, {head, body}
end

function Nibs.encode_map(map)
    local total = 0
    local body = {}
    for k, v in pairs(map) do
        local size, entry = Nibs.encode_any(k)
        insert(body, entry)
        total = total + size
        size, entry = Nibs.encode_any(v)
        insert(body, entry)
        total = total + size
    end
    local size, head = encode_pair(7, total)
    return size + total, {head, body}
end


---@param val any
function Nibs.encode_any(val)
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
            return Nibs.encode_list(val)
        else
            return Nibs.encode_map(val)
        end
    else
        error("Unsupported value type: " .. kind)
    end
end

function Nibs.encode(val)
    local i = 0
    local size, data = Nibs.encode_any(val)
    local buf = Buffer(size)
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

return Nibs
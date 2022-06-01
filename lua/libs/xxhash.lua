local bit = require 'bit'
local lshift = bit.lshift
local rshift = bit.rshift
local band = bit.band
local bxor = bit.bxor

local ffi = require 'ffi'
local cast = ffi.cast
local sizeof = ffi.sizeof

local U8Ptr = ffi.typeof "uint8_t*"
local U32Ptr = ffi.typeof "uint32_t*"
local U64 = ffi.typeof "uint64_t"
local U32 = ffi.typeof "uint32_t"

local prime32_1 = 2654435761
local prime32_2 = 2246822519
local prime32_3 = 3266489917
local prime32_4 = 668265263
local prime32_5 = 374761393

local prime64_1 = 11400714785074694791ULL
local prime64_2 = 14029467366897019727ULL
local prime64_3 = 1609587929392839161ULL
local prime64_4 = 9650029242287828579ULL
local prime64_5 = 2870177450012600261ULL

---@param seed integer
---@param value integer
---@return integer
local function round32(seed, value)
    seed = seed + value * prime32_2
    seed = lshift(seed, 13)
    seed = seed * prime32_1
    return seed
end

---@param ptr ffi.cdata* bytes
---@param len integer
---@param seed integer u32
local function xxh32(ptr, len, seed)
    local h32
    local last = ptr + len
    local limit
    local v1, v2, v3, v4

    if len >= 16 then
        limit = last - 16
        v1 = seed + prime32_1 + prime32_2
        v2 = seed + prime32_2
        v3 = seed + 0
        v4 = seed - prime32_1

        -- For every chunk of 4 words, so 4 * 32bits = 16 bytes
        repeat
            v1 = round32(v1, ptr[0])
            ptr = ptr + 4
            v2 = round32(v2, ptr[0])
            ptr = ptr + 4
            v3 = round32(v3, ptr[0])
            ptr = ptr + 4
            v4 = round32(v4, ptr[0])
            ptr = ptr + 4
        until ptr > limit

        h32 = lshift(v1, 1)
            + lshift(v2, 7)
            + lshift(v3, 12)
            + lshift(v4, 18)

    else -- when input is smaller than 16 bytes
        h32 = seed + prime32_5
    end

    h32 = h32 + len

    -- For the remaining words not covered above, either 0, 1, 2 or 3
    while ptr + 4 <= last do
        h32 = h32 + ptr[0] * prime32_3
        h32 = lshift(h32, 17) * prime32_4
        ptr = ptr + 4
    end

    -- For the remaining bytes that didn't make a whole word,
    -- either 0, 1, 2 or 3 bytes, as 4bytes = 32bits = 1 word.
    while ptr < last do
        h32 = h32 + band(cast(U8Ptr, ptr)[0], prime32_5)
        h32 = lshift(h32, 11) * prime32_1
        ptr = ptr + 1
    end

    -- Finalise
    h32 = bxor(h32, rshift(h32, 15))
    h32 = h32 * prime32_2
    h32 = bxor(h32, rshift(h32, 13))
    h32 = h32 * prime32_3
    h32 = bxor(h32, rshift(h32, 16))
    return tonumber(U32(h32))
end

---@param acc integer u64
---@param value integer u64
---@return integer acc u64
local function round64(acc, value)
    acc = acc + value * prime64_2
    acc = lshift(acc, 31)
    acc = acc * prime64_1
    return acc
end

---@param acc integer u64
---@param value integer u64
---@return integer acc u64
local function merge_round64(acc, value)
    value = round64(0, value)
    acc = bxor(acc, value)
    acc = (acc * prime64_1) + prime64_4
    return acc
end

---@param ptr ffi.cdata* *u8
---@param len integer u64
---@param seed integer u64
local function xxh64(ptr, len, seed)
    len = U64(len)
    seed = U64(seed)
    ---@type integer u64
    local h64
    ---@type ffi.cdata* *u64
    local last = ptr + len
    ---@type ffi.cdata* *u8
    local limit
    ---@type integer u64
    local v1, v2, v3, v4

    if len >= 32 then

        limit = last - 32
        v1 = seed + prime64_1 + prime64_2
        v2 = seed + prime64_2
        v3 = seed + 0
        v4 = seed - prime64_1

        -- For every chunk of 4 words, so 4 * 64bits = 32 bytes
        repeat
            v1 = round64(v1, ptr[0])
            ptr = ptr + 8
            v2 = round64(v2, ptr[0])
            ptr = ptr + 8
            v3 = round64(v3, ptr[0])
            ptr = ptr + 8
            v4 = round64(v4, ptr[0])
            ptr = ptr + 8
        until ptr > limit

        h64 = lshift(v1, 1)
            + lshift(v2, 7)
            + lshift(v3, 12)
            + lshift(v4, 18)

        h64 = merge_round64(h64, v1)
        h64 = merge_round64(h64, v2)
        h64 = merge_round64(h64, v3)
        h64 = merge_round64(h64, v4)

        -- when input is smaller than 32 bytes
    else
        h64 = seed + prime64_5
    end

    h64 = h64 + len

    -- For the remaining words not covered above, either 0, 1, 2 or 3
    while ptr + 8 <= last do
        h64 = bxor(h64, round64(0, ptr[0]))
        h64 = lshift(h64, 27) * prime64_1 + prime64_4
        ptr = ptr + 8
    end

    -- For the remaining half word. That is when there are more than 32bits
    -- remaining which didn't make a whole word.
    if ptr + 4 <= last then
        h64 = bxor(h64, cast(U32Ptr, ptr)[0] * prime64_1)
        h64 = lshift(h64, 23) * prime64_2 + prime64_3
        ptr = ptr + 4
    end

    -- For the remaining bytes that didn't make a half a word (32bits),
    -- either 0, 1, 2 or 3 bytes, as 4bytes = 32bits = 1/2 word.
    while ptr < last do
        h64 = bxor(h64, cast(U8Ptr, ptr)[0] * prime64_5)
        h64 = lshift(h64, 11) * prime64_1
        ptr = ptr + 1
    end

    -- Finalise
    h64 = bxor(h64, rshift(h64, 33))
    h64 = h64 * prime64_2
    h64 = bxor(h64, rshift(h64, 29))
    h64 = h64 * prime64_3
    h64 = bxor(h64, rshift(h64, 32))
    return h64

end

return {
    xxh32 = xxh32,
    xxh64 = xxh64,
}

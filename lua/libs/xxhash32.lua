--- xxHash
--- https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md#xxh32-algorithm-description

local bit = require 'bit'
local rshift = bit.rshift
local rol = bit.rol
local bxor = bit.bxor
local tobit = bit.tobit

local ffi = require 'ffi'
local cast = ffi.cast

local NibLib = require 'nib-lib'
local U8Ptr = NibLib.U8Ptr
local U32Ptr = NibLib.U32Ptr
local U32 = NibLib.U32
local U64 = NibLib.U64

local PRIME32_1 = tobit(0x9E3779B1)
local PRIME32_2 = tobit(0x85EBCA77)
local PRIME32_3 = tobit(0xC2B2AE3D)
local PRIME32_4 = tobit(0x27D4EB2F)
local PRIME32_5 = tobit(0x165667B1)

local function imul32(a, b)
    return tobit(U64(U32(a)) * U64(U32(b)))
end

local function round32(acc, lane)
    acc = tobit(acc + imul32(lane, PRIME32_2))
    acc = rol(acc, 13)
    acc = imul32(acc, PRIME32_1)
    return acc
end

---@param ptr ffi.cdata* bytes
---@param len integer
---@param seed integer u32
local function xxh32(ptr, len, seed)
    local last = cast(U32Ptr, ptr + len)
    ptr = cast(U32Ptr, ptr)
    seed = tobit(U32(seed))

    local h32
    if len >= 16 then
        local acc1 = tobit(seed + PRIME32_1 + PRIME32_2)
        local acc2 = tobit(seed + PRIME32_2)
        local acc3 = tobit(seed)
        local acc4 = tobit(seed - PRIME32_1)

        -- For every chunk of 4 words, so 4 * 32bits = 16 bytes
        local limit = last - 4
        repeat
            acc1 = round32(acc1, ptr[0])
            acc2 = round32(acc2, ptr[1])
            acc3 = round32(acc3, ptr[2])
            acc4 = round32(acc4, ptr[3])
            ptr = ptr + 4
        until ptr > limit

        -- Convergence
        h32 = tobit(rol(acc1, 1) + rol(acc2, 7) + rol(acc3, 12) + rol(acc4, 18) + len)
    else -- when input is smaller than 16 bytes
        h32 = tobit(seed + len + PRIME32_5)
    end

    -- For the remaining words not covered above, either 0, 1, 2 or 3
    while ptr + 1 <= last do
        h32 = imul32(rol(tobit(h32 + imul32(ptr[0], PRIME32_3)), 17), PRIME32_4)
        ptr = ptr + 1
    end

    -- For the remaining bytes that didn't make a whole word,
    -- either 0, 1, 2 or 3 bytes, as 4bytes = 32bits = 1 word.
    ptr = cast(U8Ptr, ptr)
    last = cast(U8Ptr, last)
    while ptr < last do
        h32 = imul32(rol(tobit(h32 + imul32(ptr[0], PRIME32_5)), 11), PRIME32_1)
        ptr = ptr + 1
    end

    -- Finalize
    h32 = imul32(bxor(h32, rshift(h32, 15)), PRIME32_2)
    h32 = imul32(bxor(h32, rshift(h32, 13)), PRIME32_3)
    h32 = bxor(h32, rshift(h32, 16))
    return tonumber(U32(h32))
end

return xxh32

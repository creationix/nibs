--- xxHash
--- https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md#xxh64-algorithm-description

local bit = require 'bit'
local rshift = bit.rshift
local rol = bit.rol
local bxor = bit.bxor

local ffi = require 'ffi'
local cast = ffi.cast

local NibLib = require 'nib-lib'
local U8Ptr = NibLib.U8Ptr
local U32Ptr = NibLib.U32Ptr
local U64Ptr = NibLib.U64Ptr
local U64 = NibLib.U64

local PRIME64_1 = 0x9E3779B185EBCA87ULL
local PRIME64_2 = 0xC2B2AE3D27D4EB4FULL
local PRIME64_3 = 0x165667B19E3779F9ULL
local PRIME64_4 = 0x85EBCA77C2B2AE63ULL
local PRIME64_5 = 0x27D4EB2F165667C5ULL

local function round64(acc, value)
    acc = acc + value * PRIME64_2
    acc = rol(acc, 31)
    acc = acc * PRIME64_1
    return acc
end

local function merge_round64(acc, val)
    val = round64(0, val)
    acc = bxor(acc, val)
    acc = acc * PRIME64_1 + PRIME64_4
    return acc
end

---@param ptr ffi.cdata* *u8
---@param len integer
---@param seed integer u64
local function xxh64(ptr, len, seed)
    local last = cast(U64Ptr, ptr + len)
    ptr = cast(U64Ptr, ptr)
    seed = U64(seed)

    local h64
    if len >= 32 then
        local acc1 = seed + PRIME64_1 + PRIME64_2
        local acc2 = seed + PRIME64_2
        local acc3 = seed
        local acc4 = seed - PRIME64_1

        -- For every chunk of 4 words, so 4 * 64bits = 32 bytes
        local limit = last - 4
        repeat
            acc1 = round64(acc1, ptr[0])
            acc2 = round64(acc2, ptr[1])
            acc3 = round64(acc3, ptr[2])
            acc4 = round64(acc4, ptr[3])
            ptr = ptr + 4
        until ptr > limit

        -- Convergence
        h64 = rol(acc1, 1) + rol(acc2, 7)
            + rol(acc3, 12) + rol(acc4, 18)

        h64 = merge_round64(h64, acc1)
        h64 = merge_round64(h64, acc2)
        h64 = merge_round64(h64, acc3)
        h64 = merge_round64(h64, acc4)

    else -- when input is smaller than 32 bytes
        h64 = seed + PRIME64_5
    end

    h64 = h64 + len

    -- For the remaining words not covered above, either 0, 1, 2 or 3
    while ptr + 1 <= last do
        h64 = rol(bxor(h64, round64(0, ptr[0])), 27) * PRIME64_1 + PRIME64_4
        ptr = ptr + 1
    end

    -- For the remaining half word. That is when there are more than 32bits
    -- remaining which didn't make a whole word.
    ptr = cast(U32Ptr, ptr)
    last = cast(U32Ptr, last)
    if ptr + 1 <= last then
        h64 = rol(bxor(h64, ptr[0] * PRIME64_1), 23) * PRIME64_2 + PRIME64_3
        ptr = ptr + 1
    end

    -- For the remaining bytes that didn't make a half a word (32bits),
    -- either 0, 1, 2 or 3 bytes, as 4bytes = 32bits = 1/2 word.
    ptr = cast(U8Ptr, ptr)
    last = cast(U8Ptr, last)
    while ptr < last do
        h64 = rol(bxor(h64, ptr[0] * PRIME64_5), 11) * PRIME64_1
        ptr = ptr + 1
    end

    -- Finalize
    h64 = bxor(h64, rshift(h64, 33))
    h64 = h64 * PRIME64_2
    h64 = bxor(h64, rshift(h64, 29))
    h64 = h64 * PRIME64_3
    h64 = bxor(h64, rshift(h64, 32))
    return h64

end

return xxh64

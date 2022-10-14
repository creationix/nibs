local bit = require 'bit'
local rshift = bit.rshift
local lshift = bit.lshift
local band = bit.band

local ffi = require 'ffi'
local cast = ffi.cast
local U8Ptr = ffi.typeof 'uint8_t*'
local U16Ptr = ffi.typeof 'uint16_t*'
local U32Ptr = ffi.typeof 'uint32_t*'
local U64Ptr = ffi.typeof 'uint64_t*'

local UintPtrs = {
    [3] = U8Ptr,
    [4] = U16Ptr,
    [5] = U32Ptr,
    [6] = U64Ptr,
}
-- http://graphics.stanford.edu/~seander/bithacks.html#CountBitsSetNaive
local function popcnt(v)
    local c = 0
    while v > 0 do
        c = c + band(v, 1ULL)
        v = rshift(v, 1ULL)
    end
    return c
end

local Hamt = {}
--- Walk a HAMT index checking for matching offset output
---comment
---@param bits number bits per path segment (3 for 8 bit, 4 for 16 bit, etc...)
---@return fun(read:ByteProvider,offset:number,hash:integer):integer?
function Hamt.find(bits)
    local UintPtr = assert(UintPtrs[bits], "Invalid segment bit width")
    local width = lshift(1, bits - 3)
    local segmentMask = lshift(1, bits) - 1
    local highBit = lshift(1ULL, segmentMask)
    ---@param read ByteProvider
    ---@param offset number
    ---@param hash integer u64 hash of key
    ---@return integer? result usually an offset
    return function(read, offset, hash)
        while true do

            -- Consume the next path segment
            local segment = band(hash, segmentMask)
            hash = rshift(hash, bits)

            -- Read the next bitfield
            local bitfield = cast(UintPtr, read(offset, width))[0]
            offset = offset + width

            -- Check if segment is in bitfield
            local match = lshift(1, segment)
            if band(bitfield, match) == 0 then return end

            -- If it is, calculate how many pointers to skip by counting 1s under it.
            local skipCount = tonumber(popcnt(band(bitfield, match - 1)))

            -- Jump to the pointer and read it
            offset = offset + skipCount * width

            p { "find", read(0, 100), { offset = offset, skipCount = skipCount, width = width } }

            local ptr = cast(U8Ptr, read(offset, width))[0]

            if band(ptr, highBit) > 0 then
                -- If there is a leading 1, it's a result pointer.
                local result = band(ptr, highBit - 1)
                p("Found potential match", { ptr = ptr, result = result })
                return result
            end

            -- Otherwise it's an internal pointer and we need to continue on.
            p("Going deeper", { ptr = ptr })
            -- Follow the pointer
            offset = offset + width + ptr
        end
    end
end

return Hamt

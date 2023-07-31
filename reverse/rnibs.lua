-- Main types
local ZIGZAG = 0
local FLOAT = 1
local SIMPLE = 2
local REF = 3

local BYTES = 8
local UTF8 = 9
local HEXSTRING = 10
local LIST = 11
local MAP = 12
local ARRAY = 13
local TRIE = 14
local SCOPE = 15

-- Simple subtypes
local FALSE = 0
local TRUE = 1
local NULL = 2

local bit = require 'bit'
local arshift = bit.arshift
local lshift = bit.lshift
local bxor = bit.bxor
local bor = bit.bor

local byte = string.byte

local ffi = require 'ffi'
local ffi_string = ffi.string
local istype = ffi.istype

local U8Arr = ffi.typeof 'uint8_t[?]'
local U16Arr = ffi.typeof 'uint16_t[?]'
local U32Arr = ffi.typeof 'uint32_t[?]'
local U64Arr = ffi.typeof 'uint64_t[?]'
local U16Ptr = ffi.typeof 'uint16_t*'
local U32Ptr = ffi.typeof 'uint32_t*'
local U64Ptr = ffi.typeof 'uint64_t*'
local U8 = ffi.typeof 'uint8_t'
local U16 = ffi.typeof 'uint16_t'
local U32 = ffi.typeof 'uint32_t'
local U64 = ffi.typeof 'uint64_t'
local I8 = ffi.typeof 'int8_t'
local I16 = ffi.typeof 'int16_t'
local I32 = ffi.typeof 'int32_t'
local I64 = ffi.typeof 'int64_t'
local F32 = ffi.typeof 'float'
local F64 = ffi.typeof 'double'

--- Convert an I64 to a normal number if it's in the safe range
---@param n integer cdata I64
---@return integer|number maybeNum
local function tonumberMaybe(n)
    return (n <= 0x1fffffffffffff and n >= -0x1fffffffffffff)
        and tonumber(n)
        or n
end

--- A specially optimized version of nibs used for fast serilization
--- It's especially optimized for converting existing JSON data to nibs
--- The reverse variant is used to reduce CPU and Memory overhead of the encoder.
--- @class ReverseNibs
local ReverseNibs = {}

local converter = ffi.new 'union {double f;uint64_t i;}'
ffi.cdef [[
    #pragma pack(1)
    struct rnibs4 { // for big under 12
        unsigned int big:4; // lower 4 bits are first
        unsigned int small:4;
    };
    #pragma pack(1)
    struct rnibs8 { // for big under 256
        uint8_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
    #pragma pack(1)
    struct rnibs16 { // for big under 256
        uint16_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
    #pragma pack(1)
    struct rnibs32 { // for big under 256
        uint32_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
    #pragma pack(1)
    struct rnibs64 { // for big under 256
        uint64_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
]]

local rnibs4 = ffi.typeof 'struct rnibs4'
local rnibs8 = ffi.typeof 'struct rnibs8'
local rnibs16 = ffi.typeof 'struct rnibs16'
local rnibs32 = ffi.typeof 'struct rnibs32'
local rnibs64 = ffi.typeof 'struct rnibs64'

--- Parse a single JSON token, call in a loop for a streaming parser.
--- @param json integer[] U8Array of JSON encoded data
--- @param offset integer offset of where to start parsing
--- @param len integer length of json byte array
--- @return "string"|"bytes"|"number"|"true"|"false"|"null"|"ref"|":"|","|"{"|"}"|"["|"]"|nil token name
--- @return integer|nil start offset of first character in token
--- @return integer|nil size count of bytes in token
local function next_json_token(json, offset, len)
    while true do
        if offset >= len then break end
        local c = json[offset]
        if c == 0x0d or c == 0x0a or c == 0x09 or c == 0x20 then
            -- "\r" | "\n" | "\t" | " "
            -- Skip whitespace 
            offset = offset + 1
        elseif c == 0x5b or c == 0x5d or c == 0x7b or c == 0x7d or c == 0x3a or c == 0x2c then
            -- "[" | "]" "{" | "}" | ":" | ","
            -- Pass punctuation through as-is
            return string.char(c), offset, 1
        elseif c == 0x22  then -- double quote
            -- Parse Strings
            local first = offset
            while true do
                offset = offset + 1
                if offset > len then
                    error(string.format("Unexpected EOS at %d", offset))
                end
                c = json[offset]
                if c == 0x22 then -- double quote
                    return "string", first, (offset - first) + 1
                elseif c == 0x5c then -- backslash
                    offset = offset + 1
                end
            end
        elseif c == 0x3c then -- "<"
            -- Parse Bytes
            local first = offset
            while true do
                offset = offset + 1
                if offset > len then
                    error(string.format("Unexpected EOS at %d", offset))
                end
                c = json[offset]
                if c == 0x3e then -- ">"
                    return "bytes", first, (offset - first) + 1
                end
            end
        elseif c == 0x74 and offset + 3 < len -- "t"
            and json[offset + 1] == 0x72      -- "r"
            and json[offset + 2] == 0x75      -- "u"
            and json[offset + 3] == 0x65 then -- "e"
            return "true", offset, 4
        elseif c == 0x66 and offset + 4 < len -- "f"
            and json[offset + 1] == 0x61      -- "a"
            and json[offset + 2] == 0x6c      -- "l"
            and json[offset + 3] == 0x73      -- "s"
            and json[offset + 4] == 0x65 then -- "e"
            return "false", offset, 5
        elseif c == 0x6e and offset + 3 < len -- "n"
            and json[offset + 1] == 0x75      -- "u"
            and json[offset + 2] == 0x6c      -- "l"
            and json[offset + 3] == 0x6c then -- "l"
            return "null", offset, 4
        elseif c == 0x2d or (c >= 0x30 and c <= 0x39) then -- "-" | "0"-"9"
            
            -- Parse numbers
            local first = offset
            offset = offset + 1
            c = json[offset]
            while c >= 0x30 and c <= 0x39 do -- "0"-"9"
                offset = offset + 1
                c = json[offset]
            end
            if c == 0x2e then -- "."
                offset = offset + 1
                c = json[offset]
                while c >= 0x30 and c <= 0x39 do
                    offset = offset + 1
                    c = json[offset]
                end
            end
            if c == 0x65 or c == 0x45 then -- "e" | "E"
                offset = offset + 1
                c = json[offset]
                if c == 0x2b or c == 0x2d then -- "+" | "-"
                    offset = offset + 1
                    c = json[offset]
                end
                while c >= 0x30 and c <= 0x39 do -- "0"-"9"
                    offset = offset + 1
                    c = json[offset]
                end
            end
            return "number", first, (offset - first)
        elseif c == 0x26 then -- "&"
            -- Parse Refs
            local first = offset
            offset = offset + 1
            c = json[offset]
            while c >= 0x30 and c <= 0x39 do -- "0"-"9"
                offset = offset + 1
                c = json[offset]
            end
            return "ref", first, (offset - first)
        else
            error(string.format("Unexpected %s at %d", c, offset))
        end
    end
end

ReverseNibs.next_json_token = next_json_token

local json_escapes = {
    ["\""] = "\"",
    ["\\"] = "\\",
    ["/"] = "/",
    b = "\b",
    f = "\f",
    n = "\n",
    r = "\r",
    t = "\t",
}

local function is_integer(json, offset, limit)
    if json[offset] == 0x2d then -- "-"
        offset = offset + 1
    end
    while offset < limit do
        local c = json[offset]
        -- Abort if anything is seen that's not "0"-"9"
        if c < 0x30 or c > 0x39 then return false end
        offset = offset + 1
    end
    return true
end

local function parse_number(json, offset, size)
    assert(size > 0)
    local limit = offset + size
    if is_integer(json, offset, limit) then
        -- sign is reversed since we need to use the negative range of I64 for full precision
        -- notice that the big value accumulated is always negative.
        local sign = I64(-1)
        local big = I64(0)
        while offset < limit do
            local c = json[offset]
            if c == 0x2d then -- "-"
                sign = I64(1)
            else
                big = big * 10LL - I64(json[offset] - 0x30)
            end
            offset = offset + 1
        end

        return tonumberMaybe(big * sign)
    else
        return tonumber(ffi_string(json + offset, size), 10)
    end

end

--- Parse a JSON string into a lua string
--- @param json string
--- @return string
local function parse_string(json, first, last)
    error "TODO: parse string"
    local inner = string.sub(json, first + 1, last - 1)
    if string.find(inner, "^[^\\]*$") then
        return inner
    else
        local parts = {}
        local index = 1
        while index < last do
            local a, b = string.find(inner, "^[^\\\"]+", index)
            if a and b then
                parts[#parts + 1] = string.sub(inner, a, b)
                index = b + 1
            else
                if string.sub(inner, index, index) == "\\" then
                    index = index + 1
                    local n = string.sub(inner, index, index)
                    local e = json_escapes[n]
                    if e then
                        parts[#parts + 1] = e
                        index = index + 1
                    elseif n == "u" then
                        index = index + 1
                        local m = assert(string.match(inner, "^[0-9a-f][0-9a-f][0-9a-f][0-9a-f]", index),
                            "bad unicode escape")
                        p("m: ", m)
                        error "TODO: parse unicode escapes"
                    else
                        error(string.format("Bad string escape %q at %d", n, index))
                    end
                else
                    break
                end
            end
        end
        return table.concat(parts, '')
    end
end

--- @param json string
--- @param first integer
--- @param last integer
--- @return ffi.cdata*, integer
local function parse_bytes(json, first, last)
    error "TODO: parse bytes"
    local inner = string.sub(json, first + 1, last - 1)
    local bytes = {}
    for h in inner:gmatch("[0-9a-f][0-9a-f]") do
        bytes[#bytes + 1] = tonumber(h, 16)
    end
    local buf = U8Arr(#bytes, bytes)
    return buf, #bytes
end

---Encode a small/big pair into binary parts
---@param small integer any 4-bit unsigned integer
---@param big integer and 64-bit unsigned integer
---@return string
local function encode_pair(small, big)
    if big < 0xc then
        return ffi_string(rnibs4(big, small), 1)
    elseif big < 0x100 then
        return ffi_string(rnibs8(big, 12, small), 2)
    elseif big < 0x10000 then
        return ffi_string(rnibs16(big, 13, small), 3)
    elseif big < 0x100000000 then
        return ffi_string(rnibs32(big, 14, small), 5)
    else
        return ffi_string(rnibs64(big, 15, small), 9)
    end
end

--- Convert a signed 64 bit integer to an unsigned 64 bit integer using zigzag encoding
---@param num integer
---@return integer
local function encode_zigzag(num)
    local i = I64(num)
    return U64(bxor(arshift(i, 63), lshift(i, 1)))
end

---@param val number
---@return integer
local function encode_float(val)
    -- Use same NaN encoding as used by V8 JavaScript engine
    if val ~= val then
        return 0x7ff8000000000000ULL
    end
    converter.f = val
    return converter.i
end

--- Detect if a cdata is an integer
---@param val ffi.cdata*
---@return boolean is_int
local function isInteger(val)
    return istype(I64, val) or
        istype(I32, val) or
        istype(I16, val) or
        istype(I8, val) or
        istype(U64, val) or
        istype(U32, val) or
        istype(U16, val) or
        istype(U8, val)
end

--- Detect if a cdata is a float
---@param val ffi.cdata*
---@return boolean is_float
local function isFloat(val)
    return istype(F64, val) or
        istype(F32, val)
end

--- Detect if a number is whole or not
---@param num number|ffi.cdata*
local function isWhole(num)
    local t = type(num)
    if t == 'cdata' then
        return isInteger(num)
    elseif t == 'number' then
        return not (num ~= num or num == 1 / 0 or num == -1 / 0 or math.floor(num) ~= num)
    end
end


--- Emit a reverse nibs number
--- @param emit fun(chunk:string):integer
--- @param num number
--- @return integer number of bytes emitted
local function emit_number(emit, num)
    assert(num)
    if isWhole(num) then
        return emit(encode_pair(ZIGZAG, encode_zigzag(num)))
    else
        return emit(encode_pair(FLOAT, encode_float(num)))
    end
end

--- Convert ascii hex digit to integer
--- Assumes input is valid character [0-9a-f]
---@param code integer ascii code for hex digit
---@return integer num value of hex digit (0-15)
local function fromhex(code)
    return code - (code >= 0x61 and 0x57 or 0x30)
end

--- Emit a reverse nibs string
--- @param emit fun(chunk:string):integer
--- @param str string
--- @return integer count of bytes emitted
local function emit_string(emit, str)
    if #str % 2 == 0 and string.find(str, "^[0-9a-f]+$") then
        local len = #str / 2
        local buf = U8Arr(len)
        for i = 0, len - 1 do
            buf[i] = bor(
                lshift(fromhex(byte(str, i * 2 + 1)), 4),
                fromhex(byte(str, i * 2 + 2))
            )
        end
        emit(ffi_string(buf, len))
        return len + emit(encode_pair(HEXSTRING, len))
    end
    local len = #str
    emit(str)
    return len + emit(encode_pair(UTF8, len))
end

--- @param emit fun(chunk:string):integer
--- @param buf ffi.cdata*
--- @param len integer
--- @return integer count of bytes emitted
local function emit_bytes(emit, buf, len)
    emit(ffi_string(buf, len))
    return emit(encode_pair(BYTES, len))
end

--- Scan a JSON string for duplicated strings and large numbers
--- @param json integer[] input json document to parse
--- @param index? integer optional start index
--- @return (string|number)[]|nil
function ReverseNibs.find_dups(json, index)
    error "TODO: implement find_dups"
    index = index or 1
    local len = #json
    local counts = {}
    local depth = 0
    while index <= len do
        local token, start, size = next_json_token(json, index, len)
        if not token then break end
        assert(start and size)
        local possible_dup
        if token == "{" or token == "[" then
            depth = depth + 1
        elseif token == "}" or token == "]" then
            depth = depth - 1
        elseif token == "string" and size > start + 4 then
            possible_dup = parse_string(json, start, size)
        elseif token == "number" and size > start + 2 then
            possible_dup = parse_number(json, start, size)
        end
        if possible_dup then
            local count = counts[possible_dup]
            if count then
                counts[possible_dup] = count + 1
            else
                counts[possible_dup] = 1
            end
        end
        index = size + 1
        if depth == 0 then break end
    end

    -- Extract all repeated values
    local dup_counts = {}
    local count = 0
    for val, freq in pairs(counts) do
        if freq > 1 then
            count = count + 1
            dup_counts[count] = { val, freq }
        end
    end

    if count == 0 then return end

    -- sort by frequency descending first, then by type, then ordered normally
    table.sort(dup_counts, function(a, b)
        if a[2] == b[2] then
            local t1 = type(a[1])
            local t2 = type(b[1])
            if t1 == t2 then
                return a[1] < b[1]
            else
                return t1 > t2
            end
        else
            return a[2] > b[2]
        end
    end)

    -- Fill in dups array and return it
    local dups = {}
    for i, p in ipairs(dup_counts) do
        dups[i] = p[1]
    end
    return dups
end

--- @class ReverseNibsConvertOptions
--- @field dups? (string|number)[] optional set of values to turn into refs
--- @field filter? string[] optional list of top-level properties to keep
--- @field indexLimit? number optional limit for when to generate indices.
---                           Lists and Maps need at least this many entries.
--- @field emit? fun(chunk:string):integer optional function for streaming output

--- Convert a JSON string into a stream of reverse nibs chunks
---@param json integer[] input json as U8Array to process
---@param len integer length of bytes
---@param options? ReverseNibsConvertOptions
---@return integer final_index
---@return string|nil result buffered result when no custom emit is set
function ReverseNibs.convert(json, len, options)
    options = options or {}
    local dups = options.dups
    local emit = options.emit
    local indexLimit = options.indexLimit or 12
    local chunks
    if not emit then
        chunks = {}
        function emit(chunk)
            chunks[#chunks + 1] = chunk
            return #chunk
        end
    end

    -- zero based parsing offset into input json bytearray
    local offset = 0

    local dup_ids
    local process_value

    --- Process an object
    --- @return integer total bytes emitted
    local function process_object()
        error "TODO: process object"
        local needs
        local even = true
        local count = 0
        local offset = 0
        while true do
            local token, first, size = next_json_token(json, offset)
            assert(token and first and size, "Unexpected EOS")
            offset = size + 1
            if even and token == "}" then break end
            if needs then
                if token ~= needs then
                    error(string.format("Missing expected %q at %d", needs, first))
                end
                token, first, size = next_json_token(json, offset)
                assert(token and first and size, "Unexpected EOS")
                offset = size + 1
            end
            offset = offset + process_value(token, first, size)
            if even then
                needs = ":"
                even = false
            else
                count = count + 1
                needs = ","
                even = true
            end
        end

        -- TODO: generate Trie index and mark as Trie
        -- if count >= indexLimit then
        -- end

        return offset + emit(encode_pair(MAP, offset))
    end

    ---@param offsets integer[]
    ---@return integer
    local function emit_array_index(offsets)
        local count = #offsets
        local max = offsets[count] or 0
        ---@type ffi.ctype*
        local UArr
        ---@type 1|2|4|8
        local width
        if max < 0x100 then
            width = 1
            UArr = U8Arr
        elseif max < 0x10000 then
            width = 2
            UArr = U16Arr
        elseif max < 0x100000000 then
            width = 4
            UArr = U32Arr
        else
            width = 8
            UArr = U64Arr
        end
        local index_len = count * width
        emit(ffi_string(UArr(count, offsets), index_len))
        return index_len + emit(encode_pair(width, index_len))
    end

    --- Process an array
    --- @return integer total bytes emitted
    local function process_array()
        local needs
        local count = 0

        -- Collect local offsets for use in the r-nibs array index
        local local_offset = 0
        local offsets = {}

        -- First process the child nodes
        while true do
            local token, start, size = next_json_token(json, offset, len)
            assert(token and start and size, "Unexpected EOS")
            offset = start + size
            if token == "]" then 
                break end
            if needs then
                if token ~= needs then
                    error(string.format("Missing expected %q at %d", needs, start))
                end
                token, start, size = next_json_token(json, offset, len)
                assert(token and start and size, "Unexpected EOS")
                offset = start + size
            end
            local_offset = local_offset + process_value(token, start, size)
            count = count + 1
            offsets[count] = local_offset
            needs = ","
        end

        -- Skip index and send as LIST if it's small enough
        if count < indexLimit then
            return local_offset + emit(encode_pair(LIST, local_offset))
        end

        -- Otherwise generate index and array header
        local_offset = local_offset + emit_array_index(offsets)
        return local_offset + emit(encode_pair(ARRAY, local_offset))
    end

    local simple_false = encode_pair(SIMPLE, FALSE)
    local simple_true = encode_pair(SIMPLE, TRUE)
    local simple_null = encode_pair(SIMPLE, NULL)

    --- Process a json value
    --- @param token string
    --- @param start integer
    --- @param size integer
    --- @return integer|nil bytecount of emitted data
    function process_value(token, start, size)
        p("PROCESS VALUE", start, size, offset)
        if token == "{" then
            return process_object()
        elseif token == "[" then
            return process_array()
        elseif token == "false" then
            return emit(simple_false)
        elseif token == "true" then
            return emit(simple_true)
        elseif token == "null" then
            return emit(simple_null)
        elseif token == "number" then
            local value = assert(parse_number(json, start, size))
            local ref = dup_ids and dup_ids[value]
            if ref then return emit(encode_pair(REF, ref)) end
            return emit_number(emit, value)
        elseif token == "string" then
            local value = assert(parse_string(json, start, size))
            local ref = dup_ids and dup_ids[value]
            if ref then return emit(encode_pair(REF, ref)) end
            return emit_string(emit, value)
        elseif token == "bytes" then
            return emit_bytes(emit, parse_bytes(json, start, size))
        elseif token == "ref" then
            local ref = assert(tonumber(json:sub(start + 1, size)))
            return emit(encode_pair(REF, ref))
        else
            error(string.format("Unexpcted %s at %d", token, start))
        end
    end

    -- Emit refs targets (aka dups) first if they exist
    if dups then
        error "TODO: process dups"
        dup_ids = {}
        local offsets = {}
        for i, v in ipairs(dups) do
            dup_ids[v] = i - 1
            local t = type(v)
            if t == "number" then
                offset = offset + emit_number(emit, v)
            elseif t == "string" then
                offset = offset + emit_string(emit, v)
            else
                error("Unexpected dup type " .. t)
            end
            -- Store offsets to last byte of each entry
            offsets[i] = offset - 1
        end
        offset = offset + emit_array_index(offsets)
    end

    local token, first, count = next_json_token(json, offset, len)
    assert(token and first and count)
    offset = first + count
    local nibs_size = assert(process_value(token, first, count))

    -- Emit scope header if there were ref targets (aka dups)
    if dups then
        nibs_size = nibs_size + emit(encode_pair(SCOPE, offset))
    end

    if chunks then
        local combined = table.concat(chunks)
        assert(#combined == nibs_size)
        return nibs_size, combined
    end
    return nibs_size
end

local band = bit.band
local rshift = bit.rshift

---@param data integer[] U8Arr reverse nibs serialized binary data
---@param offset integer 0 based offset into U8Arr
---@return integer offset after decoding
---@return integer little type or width
---@return integer big value or count or size
local function decode_pair(data, offset)
    p("decode pair", offset)
    local byte = data[offset - 1]
    local little = rshift(byte, 4)
    local big = band(byte, 0xf)
    if big < 12 then
        p { bits = 4, little = little, big = big, offset = offset }
        return offset - 1, little, big
    elseif big == 12 then
        big = data[offset - 2]
        p { bits = 8, little = little, big = big, offset = offset }
        return offset - 2, little, big
    elseif big == 13 then
        big = ffi.cast(U16Ptr, data + offset - 3)[0]
        p { bits = 16, little = little, big = big, offset = offset }
        return offset - 3, little, big
    elseif big == 14 then
        big = ffi.cast(U32Ptr, data + offset - 5)[0]
        p { bits = 32, little = little, big = big, offset = offset }
        return offset - 5, little, big
    else
        big = ffi.cast(U64Ptr, data + offset - 9)[0]
        p { bits = 64, little = little, big = big, offset = offset }
        return offset - 9, little, big
    end
end

---@param data integer[]
---@param width integer
---@param offset integer
---@return integer
local function decode_pointer(data, width, offset)
    p("decode pointer", { offset = offset, width = width })
    if width == 1 then
        return data[offset]
    else
        error "TODO: decode bigger pointers"
    end
end

local function Symbol(name)
    return setmetatable({}, {
        __name = name,
        __tostring = function() return "$" .. name end,
    })
end

local DATA = Symbol "DATA"
local OFFSETS = Symbol "OFFSETS"
local FIRST = Symbol "FIRST"
local LAST = Symbol "LAST"
local WIDTH = Symbol "WIDTH"
local COUNT = Symbol "COUNT"
local INDEX_FIRST = Symbol "INDEX_FIRST"

--- Skip a value
---@param data integer[] U8Arr
---@param offset integer 0 based offset into data pointing to final byte of value
---@return integer new offset into next value
local function skip_value(data, offset)
    p("skip", { offset = offset })
    local o, l, b = decode_pair(data, offset)
    if l < 8 then
        -- inline values are done after parsing the nibs pair
        return o
    else
        -- container values also need the contents skipped
        return o - b
    end
end

---@class ReverseNibsList
local ReverseNibsList = { __name = "ReverseNibsList", __is_array_like = true }

function ReverseNibsList:__len()
    ---@type integer[]|nil array of offsets to last header byte of each value
    local offsets = rawget(self, OFFSETS)
    if not offsets then
        print("\ninitializing list...")
        ---@type integer[]  data
        local data = rawget(self, DATA)
        ---@type integer offset at end of value list
        local last = rawget(self, LAST)
        ---@type integer offset of start value list
        local first = rawget(self, FIRST)
        --- Current offset to read from
        local offset = last
        offsets = {}
        while offset > first do
            offsets[#offsets + 1] = offset
            offset = skip_value(data, offset)
            p("after skip", { offset = offset })
        end
        p("Done scanning", { offset = offset, offsets = offsets })
        table.sort(offsets)
        rawset(self, OFFSETS, offsets)
        print("")
    end
    return #offsets
end

function ReverseNibsList:__index(key)
    assert(#self)
    ---@type integer[]
    local offsets = rawget(self, OFFSETS)
    local offset = offsets[key]
    if not offset then return end
    local value = ReverseNibs.decode(rawget(self, DATA), offset)
    rawset(self, key, value)
    return value
end

function ReverseNibsList:__ipairs()
    local i = 0
    local len = #self
    return function()
        if i >= len then return end
        i = i + 1
        return i, self[i]
    end
end

ReverseNibsList.__pairs = ReverseNibsList.__ipairs

---@class ReverseNibsArray
local ReverseNibsArray = { __name = "ReverseNibsArray", __is_array_like = true, __is_indexed = true }

function ReverseNibsArray:__len()
    ---@type integer
    local count = rawget(self, COUNT)
    if not count then
        print("\ninitializing array...")
        ---@type integer[]
        local data = rawget(self, DATA)
        ---@type integer
        local last = rawget(self, LAST)
        -- Read the array index header
        local o, w, c = decode_pair(data, last)
        p { o = o, w = w, c = c }
        rawset(self, WIDTH, w)
        rawset(self, INDEX_FIRST, o - w * c + 1)
        count = c
        rawset(self, COUNT, count)
        print("")
    end
    return count
end

function ReverseNibsArray:__index(k)
    p("array index", k)
    local count = #self
    if type(k) ~= "number" or math.floor(k) ~= k or k < 1 or k > count then return end
    --- @type integer[] reverse nibs encoded binary data
    local data = rawget(self, DATA)
    --- @type integer offset to start of index
    local index_first = rawget(self, INDEX_FIRST)
    --- @type integer width of index pointers
    local width = rawget(self, WIDTH)
    local offset = decode_pointer(data, width, index_first + width * (k - 1))
    local first = rawget(self, FIRST)
    p { index_first = index_first, width = width, offset = offset, first = first }
    local v = ReverseNibs.decode(data, first + offset)
    rawset(self, k, v)
    return v
end

function ReverseNibsArray:__ipairs()
    local i = 0
    local len = #self
    return function()
        if i >= len then return end
        i = i + 1
        return i, self[i]
    end
end

ReverseNibsArray.__pairs = ReverseNibsArray.__ipairs

---Convert an unsigned 64 bit integer to a signed 64 bit integer using zigzag decoding
---@param num integer
---@return integer
local function decode_zigzag(num)
    local i = I64(num)
    local o = bxor(rshift(i, 1), -band(i, 1))
    return tonumberMaybe(o)
end

--- Convert an unsigned 64 bit integer to a double precision floating point by casting the bits
---@param val number
---@return integer
local function decode_float(val)
    p("decode_float", val)
    converter.i = val
    return converter.f
end

---@param data integer[]
---@param length integer
---@return string
local function to_hex(data, length)
    local parts = {}
    local i = 0
    while i < length do
        local b = data[i]
        i = i + 1
        parts[i] = bit.tohex(b, 2)
    end
    return table.concat(parts, ' ')
end

--- Mount a nibs binary value for lazy reading
--- when accessing properties on maps, lists, and arrays, the value
--- is decoded on the fly and memoized for faster access.
--- @param data string|integer[] binary reverse nibs encoded value
--- @return string|number|boolean|table|nil toplevel decoded value
function ReverseNibs.decode(data, length)
    if type(data) == "string" then
        if not length then length = #data end
        ---@type integer[]
        local buf = U8Arr(length)
        ffi.copy(buf, data, length)
        data = buf
    end
    assert(length, "unknown value end")
    print(string.format("decode %s", to_hex(data, length)))
    local offset = length
    local little, big
    offset, little, big = decode_pair(data, offset)
    if little == ZIGZAG then
        return decode_zigzag(big)
    elseif little == FLOAT then
        error "TODO: decode FLOAT"
    elseif little == SIMPLE then
        if big == FALSE then
            return false
        elseif big == TRUE then
            return true
        elseif big == NULL then
            return nil
        else
            error(string.format("Unknown SIMPLE %d", big))
        end
    elseif little == REF then
        error "TODO: decode REF"
    elseif little == BYTES then
        error "TODO: decode BYTES"
    elseif little == UTF8 then
        error "TODO: decode UTF8"
    elseif little == HEXSTRING then
        error "TODO: decode HEXSTRING"
    elseif little == LIST then
        return setmetatable({
            [DATA] = data,
            [FIRST] = offset - big,
            [LAST] = offset
        }, ReverseNibsList)
    elseif little == MAP then
        error "TODO: decode MAP"
    elseif little == ARRAY then
        error "TODO: decode ARRAY"
    elseif little == TRIE then
        error "TODO: decode TRIE"
    elseif little == SCOPE then
        error "TODO: decode SCOPE"
    else
        error "Unknown type"
    end
end

return ReverseNibs

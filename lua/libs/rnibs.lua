local import = _G.import or require
local HamtIndex = import "hamt-index"

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
local rshift = bit.rshift
local arshift = bit.arshift
local band = bit.band
local lshift = bit.lshift
local bxor = bit.bxor
local bor = bit.bor

local byte = string.byte

local ffi = require 'ffi'
local sizeof = ffi.sizeof
local copy = ffi.copy
local ffi_string = ffi.string
local cast = ffi.cast

local insert = table.insert

local U8Arr = ffi.typeof 'uint8_t[?]'
local U16Arr = ffi.typeof 'uint16_t[?]'
local U32Arr = ffi.typeof 'uint32_t[?]'
local U64Arr = ffi.typeof 'uint64_t[?]'
local U8Ptr = ffi.typeof 'uint8_t*'
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
--- @param json string
--- @param index integer index of where to start parsing
--- @return "string"|"bytes"|"number"|"true"|"false"|"null"|"ref"|":"|","|"{"|"}"|"["|"]"|nil token name
--- @return integer|nil start index of first character
--- @return integer|nil end index of last character
local function next_json_token(json, index)
    local len = #json
    while true do
        ::continue::
        if index > len then break end
        local c = string.sub(json, index, index)
        -- Skip whitespace
        if c == "\r" or c == "\n" or c == "\t" or c == " " then
            index = index + 1
            goto continue
            -- Pass punctuation through as-is
        elseif c == "[" or c == "]" or c == "{" or c == "}" or c == ":" or c == "," then
            return c, index, index
            -- Parse Strings
        elseif c == '"' then
            local first = index
            while true do
                index = index + 1
                if index > len then
                    error(string.format("Unexpected EOS at %d", index))
                end
                c = string.sub(json, index, index)
                if c == "\"" then
                    return "string", first, index
                elseif c == "\\" then
                    index = index + 1
                end
            end
            -- Parse keywords
        elseif c == "<" then
            local first = index
            while true do
                index = index + 1
                if index > len then
                    error(string.format("Unexpected EOS at %d", index))
                end
                c = string.sub(json, index, index)
                if c == ">" then
                    return "bytes", first, index
                end
            end
        elseif c == "t" and string.sub(json, index, index + 3) == "true" then
            return "true", index, index + 3
        elseif c == "f" and string.sub(json, index, index + 4) == "false" then
            return "false", index, index + 4
        elseif c == "n" and string.sub(json, index, index + 3) == "null" then
            return "null", index, index + 3
            -- Parse numbers
        elseif c == '-' or (c >= '0' and c <= '9') then
            local first = index
            index = index + 1
            c = string.sub(json, index, index)
            while c >= '0' and c <= '9' do
                index = index + 1
                c = string.sub(json, index, index)
            end
            if c == '.' then
                index = index + 1
                c = string.sub(json, index, index)
                while c >= '0' and c <= '9' do
                    index = index + 1
                    c = string.sub(json, index, index)
                end
            end
            if c == 'e' or c == 'E' then
                index = index + 1
                c = string.sub(json, index, index)
                if c == "-" or c == "+" then
                    index = index + 1
                    c = string.sub(json, index, index)
                end
                while c >= '0' and c <= '9' do
                    index = index + 1
                    c = string.sub(json, index, index)
                end
            end
            return "number", first, index - 1
        elseif c == "&" then
            local first = index
            index = index + 1
            c = string.sub(json, index, index)
            while c >= '0' and c <= '9' do
                index = index + 1
                c = string.sub(json, index, index)
            end
            return "ref", first, index - 1
        else
            error(string.format("Unexpected %q at %d", c, index))
        end
    end
end

ReverseNibs.next_json_token = next_json_token

--- Parse a JSON string into a lua string
--- @param json string
--- @return string
local function parse_string(json, first, last)
    local inner = string.sub(json, first + 1, last - 1)
    if string.find(json, "^[^\\]*$") then
        return inner
    else
        error "TODO: parse escaped strings"
    end
end

--- @param json string
--- @param first integer
--- @param last integer
--- @return ffi.cdata*, integer
local function parse_bytes(json, first, last)
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

--- Emit a reverse nibs number
--- @param emit fun(chunk:string):integer
--- @param num number
--- @return integer number of bytes emitted
local function emit_number(emit, num)
    if math.floor(num) == num then
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
--- @param json string input json document to parse
--- @param index? integer optional start index
--- @return (string|number)[]|nil
function ReverseNibs.find_dups(json, index)
    index = index or 1
    local len = #json
    local counts = {}
    local depth = 0
    while index <= len do
        local token, first, last = next_json_token(json, index)
        if not token then break end
        assert(first and last)
        local possible_dup
        if token == "{" or token == "[" then
            depth = depth + 1
        elseif token == "}" or token == "]" then
            depth = depth - 1
        elseif token == "string" and last > first + 4 then
            possible_dup = parse_string(json, first, last)
        elseif token == "number" and last > first + 2 then
            possible_dup = assert(tonumber(string.sub(json, first, last)))
        end
        if possible_dup then
            local count = counts[possible_dup]
            if count then
                counts[possible_dup] = count + 1
            else
                counts[possible_dup] = 1
            end
        end
        index = last + 1
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
--- @field index? integer index to start parsing (defaults to 1)

--- Convert a JSON string into a stream of reverse nibs chunks
---@param json string input json string to process
---@param options? ReverseNibsConvertOptions
---@return integer final_index
---@return string|nil result buffered result when no custom emit is set
function ReverseNibs.convert(json, options)
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

    local index = options.index or 1
    local len = #json

    local dup_ids
    local process_value

    --- Process an object
    --- @return integer total bytes emitted
    local function process_object()
        local needs
        local even = true
        local count = 0
        local offset = 0
        local offsets = {}
        while true do
            local token, first, last = next_json_token(json, index)
            assert(token and first and last, "Unexpected EOS")
            index = last + 1
            if even and token == "}" then break end
            if needs then
                if token ~= needs then
                    error(string.format("Missing expected %q at %d", needs, first))
                end
                token, first, last = next_json_token(json, index)
                assert(token and first and last, "Unexpected EOS")
                index = last + 1
            end
            offset = offset + process_value(token, first, last)
            if even then
                needs = ":"
                even = false
            else
                count = count + 1
                offsets[count] = offset - 1
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
        local offset = 0
        local offsets = {}

        -- First process the child nodes
        while true do
            local token, first, last = next_json_token(json, index)
            assert(token and first and last, "Unexpected EOS")
            index = last + 1
            if token == "]" then break end
            if needs then
                if token ~= needs then
                    error(string.format("Missing expected %q at %d", needs, first))
                end
                token, first, last = next_json_token(json, index)
                index = last + 1
            end
            offset = offset + process_value(token, first, last)
            count = count + 1
            offsets[count] = offset - 1
            needs = ","
        end

        -- Skip index and send as LIST if it's small enough
        if count < indexLimit then
            return offset + emit(encode_pair(LIST, offset))
        end

        -- Otherwise generate index and array header
        offset = offset + emit_array_index(offsets)
        return offset + emit(encode_pair(ARRAY, offset))
    end

    local simple_false = encode_pair(SIMPLE, FALSE)
    local simple_true = encode_pair(SIMPLE, TRUE)
    local simple_null = encode_pair(SIMPLE, NULL)

    --- Process a json value
    --- @param token string
    --- @param first integer
    --- @param last integer
    --- @return integer|nil
    function process_value(token, first, last)
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
            local value = assert(tonumber(string.sub(json, first, last)))
            local ref = dup_ids and dup_ids[value]
            if ref then return emit(encode_pair(REF, ref)) end
            return emit_number(emit, value)
        elseif token == "string" then
            local value = parse_string(json, first, last)
            local ref = dup_ids and dup_ids[value]
            if ref then return emit(encode_pair(REF, ref)) end
            return emit_string(emit, value)
        elseif token == "bytes" then
            return emit_bytes(emit, parse_bytes(json, first, last))
        elseif token == "ref" then
            local ref = assert(tonumber(json:sub(first + 1, last)))
            return emit(encode_pair(REF, ref))
        else
            error(string.format("Unexpcted %s at %d", token, first))
        end
    end

    local offset = 0

    -- Emit refs targets (aka dups) first if they exist
    if dups then
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

    local token, first, last = next_json_token(json, index)
    if not token then return end
    assert(first and last)
    index = last + 1
    offset = offset + process_value(token, first, last)

    -- Emit scope header if there were ref targets (aka dups)
    if dups then
        offset = offset + emit(encode_pair(SCOPE, offset))
    end

    -- assert(index == start - 1 + len)

    if chunks then
        local combined = table.concat(chunks)
        assert(#combined == offset)
        return index, combined
    end
    return index
end

return ReverseNibs

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
local SCOPE = 15
-- Simple subtypes
local FALSE = 0
local TRUE = 1
local NULL = 2

local char = string.char
local byte = string.byte

local bit = require 'bit'
local lshift = bit.lshift
local rshift = bit.rshift
local arshift = bit.arshift
local band = bit.band
local bor = bit.bor
local bxor = bit.bxor

local ffi = require 'ffi'
local sizeof = ffi.sizeof
local copy = ffi.copy
local ffi_string = ffi.string
local cast = ffi.cast
local istype = ffi.istype

local insert = table.insert

-----------------------------------
------------ FFI TYPES ------------
-----------------------------------

local U8 = ffi.typeof 'uint8_t'
local I8 = ffi.typeof 'int8_t'
local U16 = ffi.typeof 'uint16_t'
local I16 = ffi.typeof 'int16_t'
local U32 = ffi.typeof 'uint32_t'
local I32 = ffi.typeof 'int32_t'
local U64 = ffi.typeof 'uint64_t'
local I64 = ffi.typeof 'int64_t'
local F32 = ffi.typeof 'float'
local F64 = ffi.typeof 'double'

local U8Ptr = ffi.typeof 'uint8_t*'
local U16Ptr = ffi.typeof 'uint16_t*'
local U32Ptr = ffi.typeof 'uint32_t*'
local U64Ptr = ffi.typeof 'uint64_t*'

local U8Arr = ffi.typeof 'uint8_t[?]'
local U16Arr = ffi.typeof 'uint16_t[?]'
local U32Arr = ffi.typeof 'uint32_t[?]'
local U64Arr = ffi.typeof 'uint64_t[?]'

local converter = ffi.new 'union {double f;uint64_t i;}'

ffi.cdef [[
    #pragma pack(1)
    struct nibs4 { // for big under 12
        unsigned int big:4; // lower 4 bits are first
        unsigned int small:4;
    };
    #pragma pack(1)
    struct nibs8 { // for big under 256
        uint8_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
    #pragma pack(1)
    struct nibs16 { // for big under 256
        uint16_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
    #pragma pack(1)
    struct nibs32 { // for big under 256
        uint32_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
    #pragma pack(1)
    struct nibs64 { // for big under 256
        uint64_t big;
        unsigned int prefix:4;
        unsigned int small:4;
    };
]]

local nibs4 = ffi.typeof 'struct nibs4'
local nibs8 = ffi.typeof 'struct nibs8'
local nibs16 = ffi.typeof 'struct nibs16'
local nibs32 = ffi.typeof 'struct nibs32'
local nibs64 = ffi.typeof 'struct nibs64'

-------------------------------------
------------ MAIN EXPORT ------------
-------------------------------------

local Nibs = {}

--------------------------------------------------
------------ GENERIC HELPER FUNCTIONS ------------
--------------------------------------------------

--- Returns true if a table should be treated like an array (ipairs/length/etc)
--- This uses the __is_array_like metaproperty if it exists, otherwise, it
--- iterates over the pairs keys checking if they look like an array (1...n)
---@param val table
---@return boolean is_array_like
local function is_array_like(val)
    local mt = getmetatable(val)
    if mt then
        if mt.__is_array_like ~= nil then
            return mt.__is_array_like
        end
        if mt.__jsontype then -- dkjson has a __jsontype field
            if mt.__jsontype == "array" then return true end
            if mt.__jsontype == "object" then return false end
        end
    end
    local i = 1
    for key in pairs(val) do
        if key ~= i then return false end
        i = i + 1
    end
    return true
end

-- Convert a nibble to an ascii hex digit
---@param b integer nibble value
---@return integer ascii hex code
local function to_hex_code(b)
    return b + (b < 10 and 0x30 or 0x57)
end

--- Convert ascii hex digit to a nibble
--- Assumes input is valid character [0-9a-f]
---@param code integer ascii code for hex digit
---@return integer num value of hex digit (0-15)
local function from_hex_code(code)
    return code - (code >= 0x61 and 0x57 or 0x30)
end

--- Detect if a cdata is an integer
---@param val ffi.cdata*
---@return boolean is_int
local function is_cdata_integer(val)
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
local function is_cdata_float(val)
    return istype(F64, val) or
        istype(F32, val)
end

--- Detect if a number is whole or not
---@param num number|ffi.cdata*
local function is_number_whole(num)
    local t = type(num)
    if t == 'cdata' then
        return is_cdata_integer(num)
    elseif t == 'number' then
        return not (num ~= num or num == 1 / 0 or num == -1 / 0 or math.floor(num) ~= num)
    end
end

--- Convert an I64 to a normal number if it's in the safe range
---@param n integer cdata I64
---@return integer|number maybeNum
local function to_number_maybe(n)
    return (n <= 0x1fffffffffffff and n >= -0x1fffffffffffff)
        and tonumber(n)
        or n
end

---------------------------------------
------------ LEXER HELPERS ------------
---------------------------------------

-- Consume a single required digit [0-9]
---@param first integer[]
---@param last integer[]
---@return integer[] new_first
local function consume_digit(first, last)
    assert(first < last, "Unexpected EOS")
    local c = first[0]
    assert(c >= 0x30 and c <= 0x39, "Unexpected character")
    return first + 1
end

-- Consume a sequence of zero or more digits [0-9]
---@param first integer[]
---@param last integer[]
---@return integer[] new_first
local function consume_digits(first, last)
    while first < last do
        local c = first[0]
        if c < 0x30 or c > 0x39 then break end -- outside "0-9"
        first = first + 1
    end
    return first
end

-- Consume a single optional character
---@param first integer[]
---@param last integer[]
---@param c1 integer
---@param c2? integer
---@return integer[] new_first
---@return boolean did_match
local function consume_optional(first, last, c1, c2)
    if first < last then
        local c = first[0]
        if c == c1 or c == c2 then
            return first + 1, true
        end
    end
    return first, false
end

--- Is a byte a hex digit in ASCII [0-9a-fA-F]
---@param code integer
---@return boolean
local function is_hex_code(code)
    return (code <= 0x39 and code >= 0x30)
        or (code >= 0x61 and code <= 0x66)
        or (code >= 0x41 and code <= 0x46)
end

-- Is an entire slice of bytes an ASCII integer
--- @param first integer[]
--- @param last integer[]
local function is_slice_integer(first, last)
    first = consume_optional(first, last, 0x2d) "-"
    first = consume_digit(first, last)
    first = consume_digits(first, last)
    return first == last
end

------------------------------------
------------ TIBS LEXER ------------
------------------------------------

-- Parse an ASCII number into a lua number
---@param first integer[]
---@param last integer[]
---@return number|integer
local function parse_number(first, last)
    if is_slice_integer(first, last) then
        -- sign is reversed since we need to use the negative range of I64 for full precision
        -- notice that the big value accumulated is always negative.
        local sign = I64(-1)
        local big = I64(0)
        while first < last do
            local c = first[0]
            if c == 0x2d then -- "-"
                sign = I64(1)
            else
                big = big * 10LL - I64(c - 0x30)
            end
            first = first + 1
        end
        return to_number_maybe(big * sign)
    end
    return tonumber(ffi_string(first, last - first), 10)
end
Nibs.parse_number = parse_number

local highPair = nil
---@param c integer
local function utf8_encode(c)
    -- Encode surrogate pairs as a single utf8 codepoint
    if highPair then
        local lowPair = c
        c = ((highPair - 0xd800) * 0x400) + (lowPair - 0xdc00) + 0x10000
    elseif c >= 0xd800 and c <= 0xdfff then --surrogate pair
        highPair = c
        return
    end
    highPair = nil

    if c <= 0x7f then
        return char(c)
    elseif c <= 0x7ff then
        return char(
            bor(0xc0, rshift(c, 6)),
            bor(0x80, band(c, 0x3f))
        )
    elseif c <= 0xffff then
        return char(
            bor(0xe0, rshift(c, 12)),
            bor(0x80, band(rshift(c, 6), 0x3f)),
            bor(0x80, band(c, 0x3f))
        )
    elseif c <= 0x10ffff then
        return char(
            bor(0xf0, rshift(c, 18)),
            bor(0x80, band(rshift(c, 12), 0x3f)),
            bor(0x80, band(rshift(c, 6), 0x3f)),
            bor(0x80, band(c, 0x3f))
        )
    else
        error "Invalid codepoint"
    end
end

local json_escapes = {
    [0x62] = "\b",
    [0x66] = "\f",
    [0x6e] = "\n",
    [0x72] = "\r",
    [0x74] = "\t",
}

--- Parse a JSON string into a lua string
--- @param first integer[]
--- @param last integer[]
--- @return string
local function parse_string(first, last)
    -- Trim off leading and trailing double quotes
    last = last - 1
    first = first + 1
    local start = first

    -- Fast path for strings with no escapes or surrogate pairs
    local is_simple_string = true
    while first < last do
        -- TODO: look for unescaped surrogate pairs and convert to normal UTF8
        local c = first[0]
        if c == 0x5c or (c >= 0xd8 and c <= 0xdf) then -- "\\" or first byte of surrogate pair
            is_simple_string = false
            break
        end
        first = first + 1
    end

    if is_simple_string then
        first = start
        return ffi_string(first, last - first)
    end

    local parts = {}
    local allowHigh

    local function flush()
        if offset > start then
            parts[#parts + 1] = ffi_string(json + start, offset - start)
        end
        start = offset
    end

    local function write_char_code(c)
        local utf8
        utf8 = utf8_encode(c)
        if utf8 then
            parts[#parts + 1] = utf8
        else
            allowHigh = true
        end
    end

    while offset < limit do
        allowHigh = false
        local c = json[offset]
        if c >= 0xd8 and c <= 0xdf and offset + 1 < limit then -- Manually handle native surrogate pairs
            flush()
            write_char_code(bor(
                lshift(c, 8),
                json[offset + 1]
            ))
            offset = offset + 2
            start = offset
        elseif c == 0x5c then -- "\\"
            flush()
            offset = offset + 1
            if offset >= limit then
                parts[#parts + 1] = "�"
                start = offset
                break
            end
            c = json[offset]
            if c == 0x75 then -- "u"
                offset = offset + 1
                -- Count how many hex digits follow the "u"
                local hex_count = (
                    (offset < limit and ishex(json[offset])) and (
                        (offset + 1 < limit and ishex(json[offset + 1])) and (
                            (offset + 2 < limit and ishex(json[offset + 2])) and (
                                (offset + 3 < limit and ishex(json[offset + 3])) and (
                                    4
                                ) or 3
                            ) or 2
                        ) or 1
                    ) or 0
                )
                -- Emit � if there are less than 4
                if hex_count < 4 then
                    parts[#parts + 1] = "�"
                    offset = offset + hex_count
                    start = offset
                else
                    write_char_code(bor(
                        lshift(fromhex(json[offset]), 12),
                        lshift(fromhex(json[offset + 1]), 8),
                        lshift(fromhex(json[offset + 2]), 4),
                        fromhex(json[offset + 3])
                    ))
                    offset = offset + 4
                    start = offset
                end
            else
                local escape = json_escapes[c]
                if escape then
                    parts[#parts + 1] = escape
                    offset = offset + 1
                    start = offset
                else
                    -- Other escapes are included as-is
                    start = offset
                    offset = offset + 1
                end
            end
        else
            offset = offset + 1
        end
        if highPair and not allowHigh then
            -- If the character after a surrogate pair is not the other half
            -- clear it and decode as �
            highPair = nil
            parts[#parts + 1] = "�"
        end
    end
    if highPair then
        -- If the last parsed value was a surrogate pair half
        -- clear it and decode as �
        highPair = nil
        parts[#parts + 1] = "�"
    end
    flush()
    return table.concat(parts, '')
end
-- Export for unit testing
Nibs.parse_string = parse_string

---@alias LexerToken "string"|"bytes"|"number"|"true"|"false"|"null"|"ref"|":"|","|"{"|"}"|"["|"]"

--- Parse a single JSON token, call in a loop for a streaming parser.
---@param first integer[]
---@param last integer[]
--- @return LexerToken|nil token name
--- @return integer[]|nil token_first offset of before token
--- @return integer[]|nil token_last offset to after token
local function next_json_token(first, last)
    while first < last do
        local c = first[0]
        if c == 0x0d or c == 0x0a or c == 0x09 or c == 0x20 then
            -- "\r" | "\n" | "\t" | " "
            -- Skip whitespace
            first = first + 1
        elseif c == 0x5b or c == 0x5d or c == 0x7b or c == 0x7d or c == 0x3a or c == 0x2c then
            -- "[" | "]" "{" | "}" | ":" | ","
            -- Pass punctuation through as-is
            return char(c), first, first + 1
        elseif c == 0x22 then -- double quote
            -- Parse Strings
            local start = first
            while true do
                first = first + 1
                assert(first < last, "Unexpected EOS")
                c = first[0]
                if c == 0x22 then     -- double quote
                    return "string", start, first + 1
                elseif c == 0x5c then -- backslash
                    first = first + 1
                end
            end
        elseif c == 0x74 and first + 3 < last -- "t"
            and first[1] == 0x72              -- "r"
            and first[2] == 0x75              -- "u"
            and first[3] == 0x65 then         -- "e"
            return "true", first, first + 4
        elseif c == 0x66 and first + 4 < last -- "f"
            and first[1] == 0x61              -- "a"
            and first[2] == 0x6c              -- "l"
            and first[3] == 0x73              -- "s"
            and first[4] == 0x65 then         -- "e"
            return "false", first, first + 5
        elseif c == 0x6e and first + 3 < last -- "n"
            and first[1] == 0x75              -- "u"
            and first[2] == 0x6c              -- "l"
            and first[3] == 0x6c then         -- "l"
            return "null", first, first + 4
        elseif c == 0x2d                      -- "-"
            or (c >= 0x30 and c <= 0x39) then -- "0"-"9"
            local start = first
            first = first + 1

            if c == 0x2d then -- "-" needs at least one digit after
                first = consume_digit(first, last)
            end
            first = consume_digits(first, last)

            local matched
            first, matched = consume_optional(first, last, 0x2e) -- "."
            if matched then
                first = consume_digit(first, last)
                first = consume_digits(first, last)
            end

            first, matched = consume_optional(first, last, 0x45, 0x65) -- "e"|"E"
            if matched then
                first = consume_optional(first, last, 0x2b, 0x2d)      -- "+"|"-"
                first = consume_digit(first, last)
                first = consume_digits(first, last)
            end

            return "number", start, first
        else
            error(string.format("Unexpected %q", string.char(c)))
        end
    end
end

Nibs.next_json_token = next_json_token

--------------------------------------------------
------------ ENCODER HELPER FUNCTIONS ------------
--------------------------------------------------

---Encode a small/big pair into binary parts
---@param small integer any 4-bit unsigned integer
---@param big integer and 64-bit unsigned integer
---@return integer size of encoded bytes
---@return ffi.cdata* bytes as nibs struct
local function encode_pair(small, big)
    if big < 0xc then
        return 1, nibs4(big, small)
    elseif big < 0x100 then
        return 2, nibs8(big, 12, small)
    elseif big < 0x10000 then
        return 3, nibs16(big, 13, small)
    elseif big < 0x100000000 then
        return 5, nibs32(big, 14, small)
    else
        return 9, nibs64(big, 15, small)
    end
end

--- Convert a signed 64 bit integer to an unsigned 64 bit integer using zigzag encoding
---@param num integer
---@return integer
local function encode_zigzag(num)
    local i = I64(num)
    ---@diagnostic disable-next-line: return-type-mismatch, param-type-mismatch
    return U64(bxor(arshift(i, 63), lshift(i, 1)))
end

--- Convert a double precision floating point to an unsigned 64 bit integer by casting the bits
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

--------------------------------------
------------ TIBS TO NIBS ------------
--------------------------------------

--- Scan a JSON string for duplicated strings and large numbers
--- @param json integer[] input json document to parse
--- @param offset integer
--- @param limit integer
--- @return (string|number)[]|nil
function Nibs.find_dups(first, last)
    local counts = {}
    local depth = 0
    while first < last do
        local t, f, l = next_json_token(first, last)
        if not t then break end
        assert(f and l)
        local possible_dup
        if t == "{" or t == "[" then
            depth = depth + 1
        elseif t == "}" or t == "]" then
            depth = depth - 1
        elseif t == "string" and f + 4 < l then
            possible_dup = parse_string(json, f, l)
        elseif t == "number" and f + 2 < l then
            possible_dup = parse_number(json, f, l)
        end
        if possible_dup then
            local count = counts[possible_dup]
            if count then
                counts[possible_dup] = count + 1
            else
                counts[possible_dup] = 1
            end
        end
        offset = l
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

---Convert a tibs encoded string into a nibs encoded binary buffer
---@param tibs string
---@return integer[] nibs bytes
function Nibs.from_tibs(tibs)
    error "TODO: Nibs.from_tibs"
end

-------------------------------------
------------ LUA TO NIBS ------------
-------------------------------------

--------------------------------------------------
------------ DECODER HELPER FUNCTIONS ------------
--------------------------------------------------

---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@return integer[] new_last after consuming header
---@return integer little type or width
---@return integer big value or count or size
local function decode_pair(first, last)
    last = last - 1
    assert(last >= first)
    local byte = last[0]
    local little = rshift(byte, 4)
    local big = band(byte, 0xf)
    if big < 12 then
        return last, little, big
    elseif big == 12 then
        last = last - 1
        assert(last >= first)
        return last, little, cast(U8Ptr, last)[0]
    elseif big == 13 then
        last = last - 2
        assert(last >= first)
        return last, little, cast(U16Ptr, last)[0]
    elseif big == 14 then
        last = last - 4
        assert(last >= first)
        return last, little, cast(U32Ptr, last)[0]
    else
        last = last - 8
        assert(last >= first)
        return last, little, cast(U64Ptr, last)[0]
    end
end

---Convert an unsigned 64 bit integer to a signed 64 bit integer using zigzag decoding
---@param num integer
---@return integer
local function decode_zigzag(num)
    local i = I64(num)
    ---@diagnostic disable-next-line: param-type-mismatch
    local o = bxor(rshift(i, 1), -band(i, 1))
    return to_number_maybe(o)
end

--- Convert an unsigned 64 bit integer to a double precision floating point by casting the bits
---@param val integer
---@return number
local function decode_float(val)
    converter.i = val
    return converter.f
end

--------------------------------------
------------ NIBS TO TIBS ------------
--------------------------------------

-------------------------------------
------------ NIBS TO LUA ------------
-------------------------------------


-----------------------------------------------------------




---Combine binary parts into a single binary string
---@param size integer total number of expected bytes
---@param parts any parts to combine
---@return number size
---@return ffi.cdata* buffer
local function combine(size, parts)
    ---@type ffi.cdata*
    local buf = U8Arr(size)
    local offset = 0
    local function write(part)
        local t = type(part)
        if t == "number" then
            buf[offset] = part
            offset = offset + 1
        elseif t == "string" then
            local len = #part
            copy(buf + offset, part, len)
            offset = offset + len
        elseif t == "cdata" then
            local len = assert(sizeof(part))
            copy(buf + offset, part, len)
            offset = offset + len
        elseif t == "table" then
            for _, p in ipairs(part) do
                write(p)
            end
        else
            error("bad type in parts")
        end
    end

    write(parts)
    assert(offset == size)
    return size, buf
end

local encode_any
local encode_list
local encode_map
local encode_array
local generate_array_index
local encode_scope


---@class Nibs
local Nibs = {}

--- A value that can be serialized with nibs
---@alias Value ffi.cdata* | string | number | boolean | nil | Scope | Ref | table<Value,Value>

---Encode any value into a nibs encoded binary string
---@param val Value
---@return string
function Nibs.encode(val)
    local size, encoded = combine(encode_any(val))
    return ffi_string(encoded, size)
end

--- Decode a hex encoded string into a binary buffer
---@param hex string
---@return ffi.cdata* buf
local function decode_hex(hex)
    local len = #hex / 2
    local buf = U8Arr(len)
    for i = 0, len - 1 do
        buf[i] = bor(
            lshift(from_hex_code(byte(hex, i * 2 + 1)), 4),
            from_hex_code(byte(hex, i * 2 + 2))
        )
    end
    return buf
end

---@param val any
---@return integer size of encoded bytes
---@return any bytes as parts
function encode_any(val)
    local t = type(val)
    if t == "number" then
        if is_number_whole(val) then
            return encode_pair(ZIGZAG, encode_zigzag(val))
        else
            return encode_pair(FLOAT, encode_float(val))
        end
    elseif t == "string" then
        local len = #val
        if len % 2 == 0 and string.match(val, "^[0-9a-f]+$") then
            len = len / 2
            local size, head = encode_pair(HEXSTRING, len)
            return size + len, { decode_hex(val), head }
        end
        local size, head = encode_pair(UTF8, len)
        return size + len, { val, head }
    elseif t == "cdata" then
        if is_cdata_integer(val) then
            -- Treat cdata integers as integers
            return encode_pair(ZIGZAG, encode_zigzag(val))
        elseif is_cdata_float(val) then
            -- Treat cdata floats as floats
            return encode_pair(FLOAT, encode_float(val))
        else
            collectgarbage("collect")
            local len = assert(sizeof(val))
            collectgarbage("collect")
            local size, head = encode_pair(BYTES, len)
            collectgarbage("collect")
            if len > 0 then
                return size + len, { val, head }
            else
                return size, head
            end
        end
    elseif t == "boolean" then
        return encode_pair(SIMPLE, val and TRUE or FALSE)
    elseif t == "nil" then
        return encode_pair(SIMPLE, NULL)
    elseif t == "table" then
        local mt = getmetatable(val)
        if mt and mt.__is_ref then
            return encode_pair(REF, val[1])
        elseif mt and mt.__is_scope then
            return encode_scope(val)
        elseif is_array_like(val) then
            if mt and mt.__is_indexed then
                return encode_array(val)
            end
            return encode_list(val)
        else
            return encode_map(val)
        end
    else
        return encode_any(tostring(val))
    end
end

---@param list Value[]
---@return integer
---@return any
function encode_list(list)
    local total = 0
    local body = {}
    for i, v in ipairs(list) do
        local size, entry = encode_any(v)
        body[i] = entry
        total = total + size
    end
    local size, head = encode_pair(LIST, total)
    return size + total, { body, head }
end

---@param list Value[]
---@return integer
---@return any
function encode_array(list)
    local total = 0
    local body = {}
    local offsets = {}
    for i, v in ipairs(list) do
        local size, entry = encode_any(v)
        body[i] = entry
        total = total + size
        offsets[i] = total
    end
    local more, index = generate_array_index(offsets)
    total = total + more
    local size, head = encode_pair(ARRAY, total)
    return size + total, { body, index, head }
end

---@param scope Scope
---@return integer
---@return any
function encode_scope(scope)
    local total = 0

    -- first encode the refs and record their relative offsets
    local body = {}
    local offsets = {}
    for i = 1, #scope - 1 do
        local v = scope[i]
        local size, entry = encode_any(v)
        body[i] = entry
        total = total + size
        offsets[i] = total
    end

    -- Generate index header and value header
    local more, index = generate_array_index(offsets)
    total = total + more

    -- Then encode the wrapped value
    local valueSize, valueEntry = encode_any(scope[#scope])
    total = total + valueSize

    -- combine everything
    local size, head = encode_pair(SCOPE, total)
    return size + total, { body, index, valueEntry, head }
end

---@param map table<Value,Value>
---@return integer
---@return any
function encode_map(map)
    local total = 0
    local body = {}
    for k, v in pairs(map) do
        local size, entry = combine(encode_any(k))
        insert(body, entry)
        total = total + size
        size, entry = encode_any(v)
        insert(body, entry)
        total = total + size
    end
    local size, head = encode_pair(MAP, total)
    return size + total, { body, head }
end

---@private
---@param offsets integer[]
---@return number
---@return any
function generate_array_index(offsets)
    local last = 0
    local count = #offsets
    if count > 0 then
        last = offsets[count]
    end
    local index, width
    if last < 0x100 then
        width = 1
        index = U8Arr(count, offsets)
    elseif last < 0x10000 then
        width = 2
        index = U16Arr(count, offsets)
    elseif last < 0x100000000 then
        width = 4
        index = U32Arr(count, offsets)
    else
        width = 8
        index = U64Arr(count, offsets)
    end
    local more, head = encode_pair(width, count)
    return more + sizeof(index), { index, head }
end

local function Symbol(name)
    return setmetatable({}, {
        __name = name,
        __tostring = function() return "$" .. name end,
    })
end

-- Reference to array buffer so it stays alive
local DATA = Symbol "DATA"
-- pointer before values (as integer data offset)
local START = Symbol "START"
-- pointer after values (as integer data offset) (also start of index array when present)
local END = Symbol "END"

-- pointer width of array index
local WIDTH = Symbol "WIDTH"
-- pointer count of array index
local COUNT = Symbol "COUNT"

-- Array of offsets for list and map
local OFFSETS = Symbol "OFFSETS"

-- Reference to the nearest scope array
local CURRENT_SCOPE = Symbol "CURRENT_SCOPE"

---@alias Nibs.Value boolean|number|string|integer[]|Nibs.List|Nibs.Array|Nibs.Map|nil


---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@return integer[] new_last after consuming header
---@return integer[] bytes decoded value
local function decode_bytes(first, last)
    local len = last - first
    local buf = U8Arr(len)
    copy(buf, first, len)
    return first, buf
end

---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@return integer[] new_last after consuming header
---@return string utf8 decoded value
local function decode_utf8(first, last)
    return first, ffi_string(first, last - first)
end

---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@return integer[] new_last after consuming header
---@return string hex decoded value
local function decode_hexstring(first, last)
    local len = last - first
    local buf = U8Arr(len * 2)
    for i = 0, len - 1 do
        local b = first[i]
        buf[i * 2] = to_hex_code(rshift(b, 4))
        buf[i * 2 + 1] = to_hex_code(band(b, 15))
    end
    return first, ffi_string(buf, len * 2)
end

local decode_list, decode_map, decode_array, decode_scope

---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@return integer[] new_last after consuming value
local function skip_value(first, last)
    local n, l, b = decode_pair(first, last)
    last = l < 8 and n or n - b
    assert(last >= first)
    return last
end

---@param first integer[] pointer to start of slice
---@param last integer[] pointer to end of slice
---@param data integer[] original buffer (for gc ref)
---@param scope? Nibs.Array nearest nibs scope array
---@return integer[] new_last after consuming value
---@return Nibs.Value decoded_value
local function decode_value(first, last, data, scope)
    assert(last > first)

    -- Read the value header and update the upper boundary
    local type_tag, int_val
    do
        local new_last
        new_last, type_tag, int_val = decode_pair(first, last)
        assert(new_last >= first)
        last = new_last
    end

    -- Process inline types (0-7)
    if type_tag == ZIGZAG then
        return last, decode_zigzag(int_val)
    elseif type_tag == FLOAT then
        return last, decode_float(int_val)
    elseif type_tag == SIMPLE then
        if int_val == FALSE then
            return last, false
        elseif int_val == TRUE then
            return last, true
        elseif int_val == NULL then
            return last, nil
        else
            error(string.format("Unknown SIMPLE %d", int_val))
        end
    elseif type_tag == REF then
        assert(scope, "missing scope array")
        return last, scope[int_val + 1]
    elseif type_tag < 8 then
        error(string.format("Unknown inline type %d", type_tag))
    end

    -- Use the length prefix to tighten up the lower boundary
    do
        local new_first = last - int_val
        assert(new_first >= first)
        first = new_first
    end

    if type_tag == BYTES then
        return decode_bytes(first, last)
    elseif type_tag == UTF8 then
        return decode_utf8(first, last)
    elseif type_tag == HEXSTRING then
        return decode_hexstring(first, last)
    elseif type_tag == LIST then
        return decode_list(first, last, data, scope)
    elseif type_tag == MAP then
        return decode_map(first, last, data, scope)
    elseif type_tag == ARRAY then
        return decode_array(first, last, data, scope)
    elseif type_tag == SCOPE then
        return decode_scope(first, last, data, scope)
    else
        error(string.format("Unknown container type %d", type_tag))
    end
end

function decode_list(first, last, data, scope)
    return first, setmetatable({
        [START] = first,
        [END] = last,
        [DATA] = data,
        [CURRENT_SCOPE] = scope,
    }, Nibs.List)
end

function decode_map(first, last, data, scope)
    return first, setmetatable({
        [START] = first,
        [END] = last,
        [DATA] = data,
        [CURRENT_SCOPE] = scope,
    }, Nibs.Map)
end

function decode_array(first, last, data, scope)
    local n, l, b = decode_pair(first, last)
    return first, setmetatable({
        [START] = first,
        [END] = n - l * b,
        [WIDTH] = l,
        [COUNT] = b,
        [DATA] = data,
        [CURRENT_SCOPE] = scope,
    }, Nibs.Array)
end

function decode_scope(first, last, data, scope)
    local index = skip_value(first, last)
    assert(index >= first)
    local _, value
    _, scope = decode_array(first, index, data, scope)
    _, value = decode_value(index, last, data, scope)
    return first, value
end

-- Reverse a list in place
---@param list any[]
local function reverse(list)
    local len = #list
    for i = 1, rshift(len, 1) do
        local j = len - i + 1
        list[i], list[j] = list[j], list[i]
    end
end

---@param self Nibs.List|Nibs.Map
local function get_offsets(self)
    ---@type integer[][]
    local offsets = rawget(self, OFFSETS)
    if not offsets then
        ---@type integer[]
        local first = rawget(self, START)
        ---@type integer[]
        local last = rawget(self, END)
        local i = 0
        offsets = {}
        while last > first do
            i = i + 1
            offsets[i] = last
            last = skip_value(first, last)
        end
        assert(last == first)
        reverse(offsets)
        offsets[0] = first
        rawset(self, OFFSETS, offsets)
    end
    return offsets
end

---@class Nibs.List
Nibs.List = { __name = "Nibs.List", __is_array_like = true }

function Nibs.List:__len()
    return #get_offsets(self)
end

function Nibs.List:__index(key)
    if type(key) ~= "number" or math.floor(key) ~= key or key < 1 then return end
    ---@type integer[][]
    local offsets = get_offsets(self)
    if key > #offsets then return end
    ---@type integer[]
    local first = offsets[key - 1]
    local last = offsets[key]
    ---@type integer[]
    local data = rawget(self, DATA)
    ---@type Nibs.Array|nil
    local scope = rawget(self, CURRENT_SCOPE)
    local _, value = decode_value(first, last, data, scope)
    rawset(self, key, value)
    return value
end

function Nibs.List:__ipairs()
    local i = 0
    local len = #self
    return function()
        if i >= len then return end
        i = i + 1
        return i, self[i]
    end
end

Nibs.List.__pairs = Nibs.List.__ipairs

---@class Nibs.Map
Nibs.Map = { __name = "Nibs.Map", __is_array_like = false }

function Nibs.Map.__len()
    return 0
end

function Nibs.Map:__pairs()
    local offsets = get_offsets(self)
    local i = 0
    local data = rawget(self, DATA)
    local scope = rawget(self, CURRENT_SCOPE)
    return function()
        if i >= #offsets then return end
        i = i + 2
        local first = offsets[i - 2]
        local mid = offsets[i - 1]
        local last = offsets[i]
        assert(i and first and mid and last)
        local _, key = decode_value(first, mid, data, scope)
        local _, value = decode_value(mid, last, data, scope)
        rawset(self, key, value)
        return key, value
    end
end

function Nibs.Map.__ipairs()
    return function() end
end

function Nibs.Map:__index(key)
    local offsets = get_offsets(self)
    local data = rawget(self, DATA)
    local scope = rawget(self, CURRENT_SCOPE)
    for i = 0, #offsets - 1, 2 do
        local first = offsets[i]
        local mid = offsets[i + 1]
        local _, k = decode_value(first, mid, data, scope)
        if k == key then
            local last = offsets[i + 2]
            local _, value = decode_value(mid, last, data, scope)
            rawset(self, key, value)
            return value
        end
    end
end

---@class Nibs.Array
Nibs.Array = { __name = "Nibs.Array", __is_array_like = true, __is_indexed = true }

function Nibs.Array:__len()
    ---@type integer
    local count = rawget(self, COUNT)
    return count
end

function Nibs.Array:__index(k)
    ---@type integer
    local count = rawget(self, COUNT)
    if type(k) ~= "number" or math.floor(k) ~= k or k < 1 or k > count then return end
    ---@type integer
    local width = rawget(self, WIDTH)
    ---@type integer[] start of value
    local first = rawget(self, START)
    ---@type integer[] end of value, start of index
    local last = rawget(self, END)
    ---@type ffi.ctype*
    local Ptr = assert(width == 1 and U8Ptr
        or width == 2 and U16Ptr
        or width == 4 and U32Ptr
        or width == 8 and U64Ptr
        or nil, "invalid width")
    ---@type integer
    local offset = cast(Ptr, last + (k - 1) * width)[0]
    ---@type integer[]
    local data = rawget(self, DATA)
    ---@type Nibs.Array|nil
    local scope = rawget(self, CURRENT_SCOPE)
    local _, value = decode_value(first, first + offset, data, scope)
    rawset(self, k, value)
    return value
end

function Nibs.Array:__ipairs()
    local i = 0
    local len = #self
    return function()
        if i >= len then return end
        i = i + 1
        return i, self[i]
    end
end

--- @param data string|integer[] binary reverse nibs encoded value
--- @param length? integer length of binary data
function Nibs.decode(data, length)
    if type(data) == "string" then
        length = length or #data
        local buf = U8Arr(length)
        copy(buf, data, length)
        data = buf
    end
    assert(length, "unknown length")
    assert(length > 0, "empty data")
    local offset, value = decode_value(data, data + length, data)
    assert(offset - data == 0)
    return value
end

---@param json string
---@return Nibs.Value
function Nibs.from_json(json)
end

return Nibs

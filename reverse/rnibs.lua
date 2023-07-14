local StreamingJsonParse = require './json-parse'

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

local ffi = require 'ffi'

local bit = require 'bit'
local rshift = bit.rshift
local arshift = bit.arshift
local band = bit.band
local lshift = bit.lshift
local bxor = bit.bxor

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


--- Parse a JSON string into a lua string
--- @param json string
--- @return string
local function parse_string(json)
    if string.find(json, "^\"[^\\]*\"$") then
        return string.sub(json, 2, #json - 1)
    else
        error "TODO: parse string"
    end
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
--- @param emit fun(chunk:string)
--- @param num number
local function emit_number(emit, num)
    if math.floor(num) == num then
        return emit(encode_pair(ZIGZAG, encode_zigzag(num)))
    else
        return emit(encode_pair(FLOAT, encode_float(num)))
    end
end

--- Emit a reverse nibs string
--- @param emit fun(chunk:string)
--- @param str string
local function emit_string(emit, str)
    -- TODO: hexstring optimization
    emit(str)
    return emit(encode_pair(UTF8, #str))
end

--- A specially optimized version of nibs used for fast serilization
--- It's especially optimized for converting existing JSON data to nibs
--- The reverse variant is used to reduce CPU and Memory overhead of the encoder.
--- @class ReverseNibs
local ReverseNibs = {}

--- Scan a JSON string for duplicated strings and large numbers
--- @param json string input json document to parse
--- @return table<string|number,boolean>|nil
function ReverseNibs.find_dups(json)
    local index = 1
    local len = #json
    local counts = {}
    while index <= len do
        local token, first, last = StreamingJsonParse.next(json, index)
        if not token then break end
        if first and last and last - first > 2 then
            local possible_dup
            if token == "string" then
                possible_dup = parse_string(string.sub(json, first, last))
            elseif token == "number" then
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
        end
        index = last + 1
    end
    local dups = {}
    for k, v in next, counts do
        if v > 1 then
            dups[k] = true
        end
    end
    return #dups > 0 and dups or nil
end

--- @class ReverseNibsConvertOptions
--- @field dups? table<string|number,boolean> optional set of values to turn into refs
--- @field filter? string[] optional list of top-level properties to keep
--- @field indexLimit? number optional limit for when to generate indices.
---                           Lists and Maps need at least this many entries.
--- @field emit? fun(chunk:string) optional function for streaming output

--- Convert a JSON string into a stream of reverse nibs chunks
---@param json string input json string to process
---@param options? ReverseNibsConvertOptions
---@return number|string result (count of chunks when streaming or buffered result)
function ReverseNibs.convert(json, options)
    options = options or {}
    local dups = options.dups
    local emit = options.emit
    local chunks
    local count = 0
    if not emit then
        chunks = {}
        function emit(chunk) chunks[#chunks + 1] = chunk end
    end

    local index = 1
    local len = #json

    local process_value

    local function process_object()
        local needs
        local even = true
        while true do
            local token, first, last = StreamingJsonParse.next(json, index)
            index = last + 1
            if even and token == "}" then
                error "TODO: end object"
            end
            if needs then
                if token ~= needs then
                    error(string.format("Missing expected %q at %d", needs, first))
                end
                token, first, last = StreamingJsonParse.next(json, index)
                index = last + 1
            end
            process_value(token, first, last)
            if even then
                needs = ":"
                even = false
            else
                needs = ","
                even = true
            end
        end
    end

    local function process_array()
        local needs
        while true do
            local token, first, last = StreamingJsonParse.next(json, index)
            index = last + 1
            if token == "]" then
                error "TODO: end array"
            end
            if needs then
                if token ~= needs then
                    error(string.format("Missing expected %q at %d", needs, first))
                end
                token, first, last = StreamingJsonParse.next(json, index)
                index = last + 1
            end
            process_value(token, first, last)
            needs = ","
        end
    end

    function process_value(token, first, last)
        if token == "{" then
            return process_object()
        elseif token == "[" then
            return process_array()
        elseif token == "false" then
            emit "\x20"
        elseif token == "true" then
            emit "\x21"
        elseif token == "null" then
            emit "\x22"
        elseif token == "number" then
            local value = assert(tonumber(string.sub(json, first, last)))
            emit_number(emit, value)
        elseif token == "string" then
            local value = parse_string(string.sub(json, first, last))
            emit_string(emit, value)
        else
            error(string.format("Unexpcted %s at %d", token, first))
        end
    end

    while index <= len do
        local token, first, last = StreamingJsonParse.next(json, index)
        if not token then break end
        index = last + 1
        process_value(token, first, last)
    end

    if dups then
        error "TODO: emit scope"
    end

    if chunks then
        return table.concat(chunks)
    else
        return count
    end
end

return ReverseNibs

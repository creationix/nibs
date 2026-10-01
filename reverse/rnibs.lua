
--- @param json integer[]
--- @param offset integer
--- @return ffi.cdata*, integer
local function parse_bytes(json, offset, limit)
    limit = limit - 1   -- subtract one to ignore trailing ">"
    offset = offset + 1 -- add one to ignore leading "<"
    local start = offset

    -- Count number of hex chars
    local hex_count = 0
    while offset < limit do
        local c = json[offset]
        if ishex(c) then
            hex_count = hex_count + 1
        else
            -- only whitespace is allowed between hex chars
            assert(c == 0x09 or c == 0x0a or c == 0x0d or c == 0x20)
        end
        offset = offset + 1
    end

    local byte_count = rshift(hex_count, 1)
    local buf = U8Arr(byte_count)
    -- target offset into buf
    local o = 0
    -- storage for partially parsed byte
    local b
    offset = start
    while offset < limit do
        local c = json[offset]
        if ishex(c) then
            if b then
                buf[o] = bor(b, fromhex(c))
                o = o + 1
                b = nil
            else
                b = lshift(fromhex(c), 4)
            end
        end
        offset = offset + 1
    end
    return buf, byte_count
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
--- @param offset integer
--- @param limit integer
--- @return (string|number)[]|nil
function ReverseNibs.find_dups(json, offset, limit)
    local counts = {}
    local depth = 0
    while offset < limit do
        local t, o, l = next_json_token(json, offset, limit)
        if not t then break end
        assert(o and l)
        local possible_dup
        if t == "{" or t == "[" then
            depth = depth + 1
        elseif t == "}" or t == "]" then
            depth = depth - 1
        elseif t == "string" and o + 4 < l then
            possible_dup = parse_string(json, o, l)
        elseif t == "number" and o + 2 < l then
            possible_dup = parse_number(json, o, l)
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

---@param json integer[]
---@param offset integer
---@param limit integer
---@return integer
local function skip_value(json, offset, limit)
    local t, _, l = next_json_token(json, offset, limit)
    if not l then return offset end
    offset = l
    if t == "{" then
        while offset < limit do
            t, _, l = next_json_token(json, offset, limit)
            if not l then return offset end
            offset = l
            if t == "}" then
                return offset
            else
                offset = skip_value(json, offset, limit)
            end
        end
    elseif t == "[" then
        while offset < limit do
            t, _, l = next_json_token(json, offset, limit)
            if not l then return offset end
            offset = l
            if t == "]" then
                return offset
            else
                offset = skip_value(json, offset, limit)
            end
        end
    elseif t == "]" or t == "}" or t == ":" or t == "," then
        error("Unexpected token " .. t)
    end
    return offset
end

--- @class ReverseNibsConvertOptions
--- @field dups? (string|number)[] optional set of values to turn into refs
--- @field filter? string[] optional list of top-level properties to keep
--- @field arrayLimit? number optional limit for when to generate indices.
---                           Lists and Maps need at least this many entries.
--- @field trieLimit? number optional limit for when to generate indices.
---                           Lists and Maps need at least this many entries.
--- @field emit? fun(chunk:string):integer optional function for streaming output

--- Convert a JSON string into a stream of reverse nibs chunks
---@param json integer[] input json as U8Array to process
---@param offset integer
---@param len integer length of bytes
---@param options? ReverseNibsConvertOptions
---@return integer final_index
---@return string|nil result buffered result when no custom emit is set
function ReverseNibs.convert(json, offset, len, options)
    options = options or {}
    local dups = options.dups
    local emit = options.emit
    local arrayLimit = options.arrayLimit or 12
    local trieLimit = options.trieLimit or (1 / 0)
    local chunks
    if not emit then
        chunks = {}
        function emit(chunk)
            chunks[#chunks + 1] = chunk
            return #chunk
        end
    end

    ---@type table<string|number, integer>|nil
    local dup_ids
    local process_value

    --- Process an object
    --- @return integer total bytes emitted
    local function process_object()
        local needs
        local even = true
        local count = 0
        local written = 0
        while true do
            local t, o, l = next_json_token(json, offset, len)
            assert(t and o and l, "Unexpected EOS")
            offset = l
            if even and t == "}" then break end
            if needs then
                if t ~= needs then
                    error(string.format("Missing expected %q at %d", needs, o))
                end
                t, o, l = next_json_token(json, offset, len)
                assert(t and o and l, "Unexpected EOS")
                offset = l
            end
            written = written + process_value(t, o, l)
            if even then
                needs = ":"
                even = false
            else
                count = count + 1
                needs = ","
                even = true
            end
        end

        if count >= trieLimit then
            error "TODO: generate Trie index and mark as Trie"
        end

        return written + emit(encode_pair(MAP, written))
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
                break
            end
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
        if count < arrayLimit then
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
    --- @param offset integer
    --- @param limit integer
    --- @return integer|nil bytecount of emitted data
    function process_value(token, offset, limit)
        p("PROCESS VALUE", start, offset, limit)
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
            local value = parse_number(json, start, start + size)
            local ref = dup_ids and dup_ids[value]
            if ref then return emit(encode_pair(REF, ref)) end
            return emit_number(emit, value)
        elseif token == "string" then
            local value = parse_string(json, start, start + size)
            local ref = dup_ids and dup_ids[value]
            if ref then return emit(encode_pair(REF, ref)) end
            return emit_string(emit, value)
        elseif token == "bytes" then
            return emit_bytes(emit, parse_bytes(json, start, start + size))
        elseif token == "ref" then
            local ref = parse_number(json, start + 1, start + size)
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


return ReverseNibs

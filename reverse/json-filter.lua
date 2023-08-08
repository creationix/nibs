local ReverseNibs = require './rnibs'
local next_json_token = ReverseNibs.next_json_token
local parse_string = ReverseNibs.parse_string

local ffi = require 'ffi'
local copy = ffi.copy
local ffi_string = ffi.string
local U8Arr = ffi.typeof 'uint8_t[?]'

local concat = table.concat

---@param input_json string json input
---@param keep_fields table<string,boolean> map of top-level fields we wish to keep
---@return string json output
local function json_filter(input_json, keep_fields)

    -- offset into bytearray
    ---@type integer 
    local offset = 0
    -- length of bytearray
    local len = #input_json 
    -- ByteArray version of JSON for faster processing
    ---@type integer[]
    local json_bytes = U8Arr(len)
    copy(json_bytes, input_json, len)

    -- list of integer offsets in alternating pairs of offset/limit
    ---@type integer[] 
    local offsets = { 0 }

    -- States:
    -- 0 start stage
    -- 1 expecting key
    -- 2 expecting colon
    -- 3 expecting value
    -- 4 expecting end or comma
    -- 5+ inside value
    ---@type integer
    local state = 0

    -- This is set when a value should be skipped
    local should_skip = false

    while offset < len do
        local t, o, l = next_json_token(json_bytes, offset, len)
        p(offset,state,t,o,l)
        offset = l
        if state == 0 then
            if t == "{" then
                state = 3 -- Expect key next
            else
                -- stay in state 0
            end
        elseif state == 1 then
            assert(t == ":")
            state = 4
        elseif state == 2 then
            if t == "," then
                state = 3
            elseif t == "}" then
                state = 0
            else 
                error(string.format("Unexpected %q at %d", t, o))
            end
        elseif state == 3 then
        elseif state == 4 then
        else
        end
        p("TOKEN", offset, t,o,l)
        if not t then break end
        assert(o and l)

        offset = l
        if t == "{" or t == "[" then
            ---@cast t "{"|"["
            depth = depth + 1
            if depth == 1 then
                kind = t
                expected = "key"
            end
        elseif depth == 1 and kind == "{" then
            p(expected,t,o,l)
            if expected == "key" then
                assert(t == "string")
                local key = parse_string(json_bytes, o, l)
                if keep_fields[key] then
                    skip_start = nil
                else
                    skip_start = previous_comma or o
                end
                expected = "colon"
            elseif expected == "colon" then
                assert(t == ":")
                expected = "value"
            elseif expected == "value" then
                expected = "comma"
            elseif expected == "comma" then
                assert(t == "," or t == "}")
                if skip_start then
                    local skip_end = t == "," and l or o
                    if skip_start <= offsets[#offsets] then
                        offsets[#offsets] = skip_end
                    else
                        offsets[#offsets + 1] = skip_start
                        offsets[#offsets + 1] = skip_end
                    end
                    skip_start = nil
                end
                if t == "," then
                    previous_comma = o
                    expected = "key"
                elseif t == "}" then
                    depth = depth - 1
                    expected = nil
                    previous_comma = nil
                end
            end
        elseif t == "}" or t == "]" then
            depth = depth - 1
        end
    end
    offsets[#offsets + 1] = offset
    p(offsets)
    local parts = {}
    for i = 1, #offsets, 2 do
        local o, l = offsets[i], offsets[i + 1]
        p(o, l)
        parts[#parts + 1] = ffi_string(json_bytes + o, l - o)
    end
    p(parts)
    return concat(parts)
end

return json_filter

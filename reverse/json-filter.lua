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
    -- 0 start state
    -- 1 expecting key
    -- 2 expecting colon
    -- 3 expecting value
    -- 4 expecting end or comma
    -- 5+ inside value
    ---@type integer
    local state = 0

    -- This is set when a value should be skipped
    local should_skip = false

    local pair_start
    local first_pair = true

    while offset < len do
        local t, o, l = next_json_token(json_bytes, offset, len)
        -- p(state,offset,o,l,t)
        if not t then break end
        assert(o and l)
        offset = l

        if state == 0 then -- start state
            if t == "{" then
                state = 1
                pair_start = l
            end
        elseif state == 1 then -- expecting key
            if t ~= "string" then
                error(string.format("Expected string key at %d", o))
            end
            local key = parse_string(json_bytes, o, l)
            should_skip = not keep_fields[key]
            state = 2
        elseif state == 2 then -- expecting colon
            if t ~= ":" then
                error(string.format("Expecded colon at %d", o))
            end
            state = 3
        elseif state == 3 then -- expecting value
            if t == "{" or t == "[" then
                state = 5
            else
                state = 4
            end
        elseif state == 4 then
            local pair_end = t == "," and first_pair and l or o
            if should_skip then
                if offsets[#offsets] >= pair_start then
                    offsets[#offsets] = pair_end
                else
                    offsets[#offsets + 1] = pair_start
                    offsets[#offsets + 1] = pair_end
                end
            else
                first_pair = false
            end
            if t == "," then
                state = 1
                pair_start = o
            elseif t == "}" then
                state = 0
            else
                error(string.format("Expected comma or brace at %d", o))
            end
        elseif state >= 5 then
            if t == "{" or t == "[" then
                state = state + 1
            elseif t == "}" or t == "]" then
                state = state - 1
            end
        else
            error "Invalid state"
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

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
    -- First convert to bytearray for faster processing
    local len = #input_json
    ---@type integer[]
    local json_bytes = U8Arr(len)
    copy(json_bytes, input_json, len)

    ---@type integer[] list of integer offsets in alternating pairs of offset/limit
    local offsets = { 0 }
    local offset = 0
    local depth = 0
    ---@type "{"|"["|nil
    local kind
    ---@type "key"|"colon"|"value"|"comma"|nil
    local expected
    ---@type integer|nil position of previous comma before a potentially skipped key/value pair
    local previous_comma
    ---@type integer|nil
    local skip_start
    while offset < len do
        local t, o, l = next_json_token(json_bytes, offset, len)
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
local ReverseNibs = require './rnibs'
local ffi = require 'ffi'
local copy = ffi.copy
local ffi_string = ffi.string
local U8Arr = ffi.typeof 'uint8_t[?]'

---@param input_json string json input
---@param keep_fields table<string,boolean> map of top-level fields we wish to keep
---@return string json output
local function meta_filter(input_json, keep_fields)
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
        local t, o, l = ReverseNibs.next_json_token(json_bytes, offset, len)
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
                local key = ReverseNibs.parse_string(json_bytes, o, l)
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
    return table.concat(parts)
end


local tests = {
    '{"name":"Filter","age":100}', {name=true},'{"name":"Filter"}',
    '{"name":"Filter","age":100}', {age=true},'{"age":100}',
    '{"name":"Filter","age":100}', {name=true,age=true},'{"name":"Filter","age":100}',
    '{"name":"Filter","age":100}', {},'{}',
}
for i = 1, #tests, 3 do
    local input_json = tests[i]
    ---@type table<string,boolean>
    local keep_fields = tests[i+1]
    local expected_output_json = tests[i+2]
    local actual_output_json = meta_filter(input_json, keep_fields)
    p(input_json,keep_fields,actual_output_json,expected_output_json)
    assert(expected_output_json == actual_output_json, "JSON mismatch")
end
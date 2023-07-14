--- @class StreamingJsonParse
local StreamingJsonParse = {}

--- Parse a single JSON token
--- @param json string
--- @param index integer
--- @return "string"|"number"|"true"|"false"|"null"|":"|","|"{"|"}"|"["|"]"|nil token name
--- @return integer|nil start index of first character
--- @return integer|nil end index of last character
function StreamingJsonParse.next(json, index)
    local len = #json
    while true do
        ::continue::
        if index > len then break end
        local c = string.sub(json, index, index)
        -- Skip whitespace
        if c == "\r" or c == "\n" or c == "\t" or c == " " then
            index = index + 1
            goto continue
        elseif c == "[" or c == "]" or c == "{" or c == "}" or c == ":" or c == "," then
            return c, index, index
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
        elseif c == "t" and string.sub(json, index, index + 3) == "true" then
            return "true", index, index + 3
        elseif c == "f" and string.sub(json, index, index + 4) == "false" then
            return "false", index, index + 4
        elseif c == "n" and string.sub(json, index, index + 3) == "null" then
            return "null", index, index + 3
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
        else
            error(string.format("Unexpected %q at %d", c, index))
        end
    end
end

return StreamingJsonParse
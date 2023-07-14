local StreamingJsonParse = require './json-parse'

--- A specially optimized version of nibs used for fast serilization
--- It's especially optimized for converting existing JSON data to nibs
--- The reverse variant is used to reduce CPU and Memory overhead of the encoder.
--- @class ReverseNibs
local ReverseNibs = {}


--- Scan a JSON string for duplicated strings and large numbers
--- @param json string input json document to parse
--- @return (string|number)[]|nil
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
                possible_dup = string.sub(json, first, last)
                if string.find(possible_dup, "^\"[^\\]*\"$") then
                    possible_dup = string.sub(json, first + 1, last - 1)
                else
                    error "TODO: parse string"
                end
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
            dups[#dups + 1] = k
        end
    end
    return #dups > 0 and dups or nil
end

--- @class ReverseNibsConvertOptions
--- @field dups? (string|number)[] optional list of values to turn into refs
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
    local emit = options.emit
    local chunks
    local count = 0
    if not emit then
        chunks = {}
        function emit(chunk) chunks[#chunks + 1] = chunk end
    end

    local index = 1
    local len = #json
    while index <= len do
        local token, first, last = StreamingJsonParse.next(json, index)
        p { token = token, first = first, last = last }
        error "TODO: Implement ReverseNibs.convert"
    end

    if chunks then
        return table.concat(chunks)
    else
        return count
    end
end

return ReverseNibs

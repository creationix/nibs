local NibLib = {}

-- Returns true if a table should be treated like an array (ipairs/length/etc)
function NibLib.isArrayLike(val)
    local mt = getmetatable(val)
    if mt and mt.__is_array_like ~= nil then
        return mt.__is_array_like
    end
    local i = 1
    for key in pairs(val) do
        if key ~= i then return false end
        i = i + 1
    end
    return true
end

return NibLib

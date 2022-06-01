local bit = require 'bit'
local bxor = bit.bxor
local rol = bit.rol
local lshift = bit.lshift
local band = bit.band
local bor = bit.bor

local function gimli(state)
    for round = 24, 1, -1 do
        for column = 0, 3, 1 do
            local x = rol(state[column], 24)
            local y = rol(state[4 + column], 9)
            local z = state[8 + column]

            state[8 + column] = bxor(x, lshift(z, 1), lshift(band(y, z), 2))
            state[4 + column] = bxor(y, x, lshift(bor(x, z), 1))
            state[column] = bxor(z, y, lshift(band(x, y), 3))
        end

        local t = band(round, 3)
        if t == 2 then
            -- big swap: pattern ..S...S...S. etc.
            state[0], state[2] = state[2], state[0]
            state[1], state[3] = state[3], state[1]
        elseif t == 0 then
            -- small swap: pattern s...s...s... etc.
            state[0], state[1] = state[1], state[0]
            state[2], state[3] = state[3], state[2]
            -- add constant: pattern c...c...c... etc.
            state[0] = bxor(state[0], bor(0x9e377900, round))
        end

    end
end

return gimli

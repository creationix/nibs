-- Stats were collected running nibs encoding on a large dataset
-- and recorded a histogram of what bit size was needed for encoding
-- the big half.
local bitstats = {
    [0] = 479,
    [1] = 43786,
    [2] = 54276,
    [3] = 46792,
    [4] = 40542,
    [5] = 59089,
    [6] = 25338,
    [7] = 64306,
    [8] = 7138,
    [9] = 1972,
    [10] = 1989,
    [11] = 1739,
    [12] = 198,
    [13] = 272,
    [14] = 334,
    [15] = 443,
    [16] = 494,
    [17] = 709,
    [18] = 763,
    [19] = 224,
    [20] = 111,
    [21] = 79,
    [22] = 34,
    [23] = 9,
    [24] = 4,
    [25] = 5,
    [26] = 1,
}

-- bigger dataset
bitstats = { [0] = 5177, 70664, 86123, 65649, 91297, 93374, 21744, 154290, 22574, 4613, 1457, 1944,
    2003, 2578, 3190, 3875, 3964, 4383, 3994, 2740, 1224, 876, 327, 274, 134, 55, 31, 12,
    [42] = 2 }

-- even bigger dataset
bitstats = { [0] = 127106, 1771178, 1926644, 1785941, 2542469, 2445852, 636775, 3586448, 723134, 82320, 29072, 32728, 40278, 43259, 48099,
    64305, 71506, 89417, 95192, 86348, 40145, 28090, 8891, 3852, 1179, 635, 291, 97, 5, 1, 1, [42] = 129 }

local options = {
    nibsv1 = {
        { 0.5, 3.585 }, -- xxxx under 12
        { 1.5, 8 }, -- 1100 ...[1](8-bit)
        { 2.5, 16 }, -- 1101 ...[2](16-bit)
        { 4.5, 32 }, -- 1110 ...[4](32-bit)
        { 8.5, 64 }, -- 1111 ...[8](64-bit)
    },
    -- stores u32 values using 1-5 bytes
    varint4 = {
        { 0.5, 3 }, -- 0xxx ...[0](3-bit)
        { 1.5, 10 }, -- 10xx ...[1](10-bit)
        { 2.5, 17 }, -- 110x ...[2](17-bit)
        { 3.5, 24 }, -- 1110 ...[3](24-bit)
        { 4.5, 32 }, -- 1111 ...[4](32-bit)
    },
    -- stores u32 values using 1-5 bytes
    varint4c = {
        { 0.5, 3 }, -- 0xxx ...[0](3-bit)
        { 1.5, 10 }, -- 10xx ...[1](10-bit)
        { 2.5, 17 }, -- 110x ...[2](17-bit)
        { 3.5, 24 }, -- 1110 ...[3](24-bit)
        { 8.5, 64 }, -- 1111 ...[8](64-bit)
    },
    -- stores u64 values using 1-9 bytes
    varint4x2 = {
        { 0.5, 3 }, -- 0xxx ...[0](3-bit)
        { 2.5, 18 }, -- 10xx ...[2](18-bit)
        { 4.5, 33 }, -- 110x ...[4](33-bit)
        { 6.5, 48 }, -- 1110 ...[6](48-bit)
        { 8.5, 64 }, -- 1111 ...[8](64-bit)
    },
    -- stores u32 values using 1-5 bytes
    varint3p2 = {
        { 0.375, 2 }, -- 0xx ...[0](2-bit)
        { 1.375, 9 }, -- 10x ...[1](9-bit)
        { 2.375, 16 }, -- 110 ...[2](16-bit)
        { 4.375, 32 }, -- 111 ...[4](32-bit)
    },
    -- stores u64 values using 1-9 bytes
    varint4p2 = {
        { 0.5, 3 }, -- 0xxx ...[0](3-bit)
        { 1.5, 10 }, -- 10xx ...[1](10-bit)
        { 2.5, 17 }, -- 110x ...[2](17-bit)
        { 4.5, 32 }, -- 1110 ...[4](32-bit)
        { 8.5, 64 }, -- 1111 ...[8](64-bit)
    },
    -- stores u128 values using 1-17 bytes
    varint5p2 = {
        { 0.625, 4 }, -- 0xxxx ...[0](4-bit)
        { 1.625, 11 }, -- 10xxx ...[1](11-bit)
        { 2.625, 18 }, -- 110xx ...[2](18-bit)
        { 4.625, 33 }, -- 1110x ...[4](33-bit)
        { 8.625, 64 }, -- 11110 ...[8](64-bit)
        { 16.625, 128 }, -- 11111 ...[16](128-bit)
    },
    -- stores u64 values using 1-9 bytes
    varint4fit = {
        { 0.5, 3 }, -- 0xxx ...[0](3-bit)
        { 1.5, 10 }, -- 10xx ...[1](10-bit)
        { 3.5, 25 }, -- 110x ...[3](25-bit)
        { 7.5, 56 }, -- 1110 ...[7](56-bit)
        { 8.5, 64 }, -- 1111 ...[8](64-bit)
    },
    -- stores u64 values using 1-9 bytes
    varint8 = {
        { 1, 7 }, -- 0xxxxxxx ...[0](7-bit)
        { 2, 14 }, -- 10xxxxxx ...[1](14-bit)
        { 3, 21 }, -- 110xxxxx ...[2](21-bit)
        { 4, 28 }, -- 1110xxxx ...[3](28-bit)
        { 5, 35 }, -- 11110xxx ...[4](35-bit)
        { 6, 42 }, -- 111110xx ...[5](42-bit)
        { 7, 49 }, -- 1111110x ...[6](49-bit)
        { 8, 56 }, -- 11111110 ...[7](56-bit)
        { 9, 64 }, -- 11111111 ...[8](64-bit)
    },
    -- stores u128 values using 3-19 bytes
    varint16 = {
        { 2, 15 }, -- 0xxxxxxxxxxxxxxx ...[0](15-bit)
        { 3, 22 }, -- 10xxxxxxxxxxxxxx ...[1](22-bit)
        { 4, 29 }, -- 110xxxxxxxxxxxxx ...[2](29-bit)
        { 5, 36 }, -- 1110xxxxxxxxxxxx ...[3](36-bit)
        { 6, 43 }, -- 11110xxxxxxxxxxx ...[4](43-bit)
        { 7, 50 }, -- 111110xxxxxxxxxx ...[5](50-bit)
        { 8, 57 }, -- 1111110xxxxxxxxx ...[6](57-bit)
        { 9, 64 }, -- 11111110xxxxxxxx ...[7](64-bit)
        { 10, 71 }, -- 111111110xxxxxxx ...[8](71-bit)
        { 11, 78 }, -- 1111111110xxxxxx ...[9](78-bit)
        { 12, 85 }, -- 11111111110xxxxx ...[10](85-bit)
        { 13, 92 }, -- 111111111110xxxx ...[11](92-bit)
        { 14, 99 }, -- 1111111111110xxx ...[12](99-bit)
        { 15, 106 }, -- 11111111111110xx ...[13](106-bit)
        { 16, 113 }, -- 111111111111110x ...[14](113-bit)
        { 17, 120 }, -- 1111111111111110 ...[15](120-bit)
        { 18, 128 }, -- 1111111111111111 ...[16](128-bit)
    },
}

local results = {}
for option, levels in pairs(options) do
    local total = 0
    for bits, count in pairs(bitstats) do
        for _, level in ipairs(levels) do
            local cost, size = unpack(level)
            if size >= bits then
                total = total + count * cost
                break
            end
        end
    end
    table.insert(results, { option, total })
end
table.sort(results, function(a, b) return a[2] < b[2] end)
p(results)

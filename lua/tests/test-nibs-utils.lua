local p = require('../deps/pretty-print').prettyPrint
local colorize = require('pretty-print').colorize
local TestUtils = require 'test-utils'
local hex_dump = TestUtils.hex_dump


local Nibs = require 'nibs'
local Tibs = Nibs.Tibs
local readFileSync = require('fs').readFileSync

local filename = module.dir .. "/../../fixtures/multi-tests.tibs"
local text = assert(readFileSync(filename))
local tests = assert(Tibs.decode(text, filename))
local ffi = require 'ffi'

local function dump(name, value, big)
    print("\n" .. name .. ":")
    if type(value) == "cdata" then
        value = ffi.string(value, ffi.sizeof(value))
    end
    if type(value) == "string" then
        if big == true or big == nil and #value > 1000 then
            print(string.format("%d bytes total\n", #value))
        else
            hex_dump(value)
        end
    else
        if not big then
            p(value)
        end
    end
end
for name, input in pairs(tests) do
    print("\n\n" .. colorize("highlight", name:upper()))
    local tibs_plain = Tibs.encode(input)
    local nibs_plain = Nibs.encode(input)

    dump("input", input, #tibs_plain > 1000)
    dump("tibs", tibs_plain)
    dump("nibs", nibs_plain)

    local dups = Tibs.find_dups(tibs_plain, { min_freq = 2, min_str_len = 2, min_num_len = 3 })
    if dups then
        local nibs_with_refs = Nibs.encode(input, dups)
        local input_with_refs = Nibs.decode(nibs_with_refs, { deref = false })
        local tibs_with_refs = Tibs.encode(input_with_refs)
        dump("dups", dups)
        dump("input with refs", input_with_refs, #tibs_with_refs > 1000)
        dump("tibs with refs", tibs_with_refs)
        dump("nibs with refs", nibs_with_refs)
    else
        print("No dups found!")
    end

    local input_derefed = Nibs.decode(nibs_plain, { deref = true })
    dump("input derefed", input_derefed)
    local tibs_derefed = Tibs.encode(input_derefed)
    dump("tibs derefed", tibs_derefed)
    local nibs_derefed = Nibs.encode(input_derefed)
    dump("nibs derefed", nibs_derefed)

    dups = Tibs.find_dups(tibs_derefed, { min_freq = 2, min_str_len = 2, min_num_len = 3 })
    if dups then
        local nibs_with_refs = Nibs.encode(input_derefed, dups)
        local input_with_refs = Nibs.decode(nibs_with_refs, { deref = false })
        local tibs_with_refs = Tibs.encode(input_with_refs)
        dump("dups", dups)
        dump("input re-ref", input_with_refs, #tibs_with_refs > 1000)
        dump("tibs re-ref", tibs_with_refs)
        dump("nibs re-ref", nibs_with_refs)
    else
        print("No dups found in reref!")
    end

    local expected_tibs = Tibs.encode(input)
    local actual_tibs = Tibs.encode(Nibs.decode(Nibs.encode(Tibs.decode(expected_tibs)),{deref=false}))
    assert(expected_tibs == actual_tibs, "Tibs encode/decode roundtrip failed!")
end

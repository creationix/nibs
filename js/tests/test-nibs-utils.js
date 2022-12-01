import { readFileSync } from 'node:fs'
import { join as pathJoin } from 'node:path'
import { fileURLToPath } from 'node:url';
import { inspect } from 'node:util'

import { isRef, isScope, isIndexed } from "../symbols.js"
import * as Tibs from '../tibs.js'
import * as Nibs from '../nibs.js'

const filename = pathJoin(fileURLToPath(import.meta.url), '../../../fixtures/multi-tests.tibs')
const inputs = Tibs.decode(readFileSync(filename, 'utf8'), filename)

function autoIndex(val) {
    return Nibs.optimize(val, 4, new Map())
}

function deduplicate(doc) {
    return Nibs.optimize(doc, 1 / 0)
}

function optimize(doc) {
    return Nibs.optimize(doc, 4)
}

// Walk an entire document to expand lazy properties
function expand(doc) {
    const seen = new Set()
    function walk(val) {
        if (doc && typeof doc === 'object') {

            // Break cycles
            if (seen.has(doc)) return
            seen.add(doc)

            if (Array.isArray(doc)) {
                doc.forEach(walk)
            } else {
                for (const [k, v] of Object.entries(doc)) {
                    walk(k)
                    walk(v)
                }
            }
        }
    }
    walk(doc)
    return doc
}

const tests = {
    // "Original": [],
    // "Original -> Json": [Tibs.encode],
    // "Original -> Json -> JS": [Tibs.encode, Tibs.decode],
    // "Original -> Json -> JS -> Json": [Tibs.encode, Tibs.decode, Tibs.encode],
    // "Original -> Json -> JS -> Nibs": [Tibs.encode, Tibs.decode, Nibs.encode],
    // "Original -> Nibs": [Nibs.encode],
    // "Original -> Nibs -> JS": [Nibs.encode, Nibs.decode],
    // "Deduplicated": [deduplicate],
    // "Deduplicated -> Json": [deduplicate, Tibs.encode],
    // "Deduplicated -> Json -> JS": [deduplicate, Tibs.encode, Tibs.decode],
    // "Deduplicated -> Nibs": [deduplicate, Nibs.encode],
    // "Deduplicated -> Nibs -> JS": [deduplicate, Nibs.encode, Nibs.decode],
    // "Indexed": [autoIndex],
    // "Indexed -> Json": [autoIndex, Tibs.encode],
    // "Indexed -> Json -> JS": [autoIndex, Tibs.encode, Tibs.decode],
    // "Indexed -> Json -> JS -> Json": [autoIndex, Tibs.encode, Tibs.decode, Tibs.encode],
    // "Indexed -> Nibs": [autoIndex, Nibs.encode],
    // "Indexed -> Nibs -> JS": [autoIndex, Nibs.encode, Nibs.decode],
    // "Optimized": [optimize],
    // "Optimized -> Json": [optimize, Tibs.encode],
    // "Optimized -> Json -> JS": [optimize, Tibs.encode, Tibs.decode],
    // "Optimized -> Nibs": [optimize, Nibs.encode],
    "Optimized -> Nibs -> JS": [optimize, Nibs.encode, Nibs.decode],
    "Optimized -> Nibs -> JS -> Expanded": [optimize, Nibs.encode, Nibs.decode, expand],
}

const matchers = [
    [
        "Original",
        "Original -> Json -> JS",
        "Original -> Nibs -> JS",
    ],
    [
        "Original -> Json",
        "Original -> Json -> JS -> Json",
    ],
    [
        "Original -> Nibs",
        "Original -> Json -> JS -> Nibs",
    ],
    [
        "Deduped",
        "Deduped -> Json -> JS",
        // "Deduped -> Nibs -> JS",
    ],
    [
        "Deduped -> Json",
        "Deduped -> Json -> JS -> Json",
    ],
    [
        "Indexed",
        "Indexed -> Json -> JS",
        // "Indexed -> Nibs -> JS",
    ],
    [
        "Indexed -> Json",
        "Indexed -> Json -> JS -> Json",
    ],
]

for (const [name, value] of Object.entries(inputs)) {

    for (const [test, actions] of Object.entries(tests)) {
        let result = value
        for (const action of actions) {
            result = action(result)
        }
        console.log(inspect({ name, test, result }, true, 3, true))
    }
}

// local extra_space = ""
// for name, json in pairs(inputs) do
//     local outputs = {}
//     local big = #json > 1000
// print("\n\n"..colorize("highlight", name: upper()))
// for test, list in pairs(tests) do
//     print(extra_space..colorize("success", test))
//         local value = json
// for _, step in ipairs(list) do
//     if type(step) == "table" then
//                 local fn = step[1]
//                 local args = { unpack(step, 2) }
// step = function (val)
//                     return fn(val, unpack(args))
// end
// end
// collectgarbage("collect")
// value = assert(step(value))
// collectgarbage("collect")
// end
// outputs[test] = value
// if type(value) == "string" then
// if big then
// print(string.format("%d bytes total\n", #value))
//             else
// hex_dump(value)
// end
// extra_space = ""
//         else
// if not big then
// p(value)
// end
// extra_space = "\n"
// end
// end
// for _, group in ipairs(matchers) do
//         local first = group[1]
//         local expected = outputs[first]
// for i = 2, #group do
//             local other = group[i]
//             local actual = outputs[other]
// if expected and actual and not TestUtils.equal(expected, actual) then
// print(string.format("Expected (%s):", first))
// p(expected)
// print(string.format("Actual (%s):", other))
// p(actual)
// error(name.. " Mismatch in expected same outputs")
// end
// end
// end
// end

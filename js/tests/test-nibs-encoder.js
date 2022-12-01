import { readFileSync } from 'fs'
import { join as pathJoin } from 'path'
import { fileURLToPath } from 'url';

import * as Tibs from '../tibs.js'
import * as Nibs from '../nibs.js'
import { inspect } from 'util';

const filename = pathJoin(fileURLToPath(import.meta.url), '../../../fixtures/encoder-fixtures.tibs')
/** @type {Map} */
const tests = Tibs.decode(readFileSync(filename, 'utf8'), filename)

function highlight(str) {
    return `\x1b[38;5;45;48;5;236m${str}\x1b[0m`
}

/**
 * 
 * @param {Uint8Array} a 
 * @param {Uint8Array} b 
 * @returns {boolean}
 */
function same(a, b) {
    if (a.length !== b.length) return false
    for (let i = 0, l = a.length; i < l; i++) {
        if (a[i] !== b[i]) return false
    }
    return true
}

for (const [name, list] of tests.entries()) {
    console.log(`\n${highlight(name)}`)
    for (let i = 0; i < list.length; i += 2) {
        const input = list[i];
        const expected = list[i + 1]
        const actual = Nibs.encode(input)
        console.log("\nInput    " + inspect(input, { showHidden: true, depth: 2, colors: true, breakLength: 100 }))
        console.log("Expected " + Buffer.from(expected).toString('hex'))
        console.log("Actual   " + Buffer.from(actual).toString('hex'))
        if (!same(expected, actual)) {
            throw new Error("Mismatch")
        }
    }
}

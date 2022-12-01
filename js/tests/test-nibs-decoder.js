import { readFileSync } from 'node:fs'
import { join as pathJoin } from 'node:path'
import { fileURLToPath } from 'node:url';
import { inspect } from 'node:util'

import { isRef, isScope, isIndexed } from "../symbols.js"
import * as Tibs from '../tibs.js'
import * as Nibs from '../nibs.js'

const filename = pathJoin(fileURLToPath(import.meta.url), '../../../fixtures/decoder-fixtures.tibs')
const tests = Tibs.decode(readFileSync(filename, 'utf8'), filename)

function highlight(str) {
    return `\x1b[38;5;45;48;5;236m${str}\x1b[0m`
}

/**
 * @param {any} a 
 * @param {any} b 
 * @returns {boolean}
 */
function same(a, b) {
    if (a === b) return true
    const t = typeof (a)
    if (t !== typeof (b)) return false
    if (a !== a && b !== b) return true // Treat two NaN values as equal
    if (t === 'object') {
        const ca = Object.prototype.toString.call(a)
        const cb = Object.prototype.toString.call(b)
        if (ca === cb) {
            if (ca === '[object Uint8Array]' || ca === '[object Array]') {
                if (a[isScope] !== b[isScope] ||
                    a[isIndexed] !== b[isIndexed] ||
                    a.length !== b.length) return false
                for (let i = 0, l = a.length; i < l; i++) {
                    if (!same(a[i], b[i])) return false
                }
                return true
            }
            if (ca === '[object Map]') {
                if (a[isIndexed] !== b[isIndexed] ||
                    a.size !== b.size) return false
                for (const [k, v] of a.entries()) {
                    if (!same(v, b.get(k))) return false
                }
                for (const [k, v] of b.entries()) {
                    if (!same(v, a.get(k))) return false
                }
                return true
            }
            if (ca === '[object Object]') {
                if (a[isIndexed] !== b[isIndexed] ||
                    a.size !== b.size) return false
                for (const [k, v] of Object.entries(a)) {
                    if (!same(v, b[b])) return false
                }
                for (const [k, v] of Object.entries(b)) {
                    if (!same(v, a[k])) return false
                }
                return true
            }

            if (ca === '[object Map]' && cb == '[object Object]') {

            }
        }
        throw "TODO " + ca + " : " + cb
    }

    return false
}

for (const [name, list] of Object.entries(tests)) {
    console.log(`\n${highlight(name)}\n`)
    for (let i = 0; i < list.length; i += 2) {
        const input = list[i];
        const expected = list[i + 1]
        const actual = Nibs.decode(input)
        const pass = same(expected, actual)
        console.log("\nInput    " + Buffer.from(input).toString('hex'))
        console.log("Expected " + inspect(expected, { showHidden: true, depth: 2, colors: true, breakLength: 100 }))
        console.log("Actual   " + inspect(actual, { showHidden: true, depth: 2, colors: true, breakLength: 100 }))
        if (!pass) {
            throw new Error("Mismatch")
        }
    }
}

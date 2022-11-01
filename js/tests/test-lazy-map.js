import * as Tibs from '../tibs.js'
import * as Nibs from '../nibs.js'
import { inspect } from 'node:util'
import { assert } from 'node:console'

const v1 = Nibs.decode(Nibs.encode(Tibs.decode('[1,2,3]')))
console.log("\nOriginal lazy array:")
console.log(inspect(v1, true, 3, true))
assert(Object.getOwnPropertyDescriptor(v1, '0')?.get)
assert(Object.getOwnPropertyDescriptor(v1, '1')?.get)
assert(Object.getOwnPropertyDescriptor(v1, '2')?.get)
expand(v1)
console.log("\nLazy array after expansion:")
console.log(inspect(v1, true, 3, true))
assert(!Object.getOwnPropertyDescriptor(v1, '0')?.get)
assert(!Object.getOwnPropertyDescriptor(v1, '1')?.get)
assert(!Object.getOwnPropertyDescriptor(v1, '2')?.get)

const v2 = Nibs.decode(Nibs.encode(Tibs.decode('{0:1,1:2,2:3}')))
console.log("\nOriginal lazy map:")
console.log(inspect(v2, true, 3, true))
assert(Object.getOwnPropertyDescriptor(v2, 'get') !== undefined)
expand(v2)
console.log("\nLazy map after expansion:")
console.log(inspect(v2, true, 3, true))
assert(Object.getOwnPropertyDescriptor(v2, 'get') === undefined)


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
                for (const [k, v] of doc.entries()) {
                    walk(k)
                    walk(v)
                }
            }
        }
    }
    walk(doc)
    return doc
}

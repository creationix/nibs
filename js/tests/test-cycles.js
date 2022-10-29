import { inspect } from 'node:util'
import * as Nibs from "../nibs.js"

/** @type {any[]} */
const cycle = [1, 2, 3]
cycle.push(cycle)
cycle.push({ cycle, cool: true })
console.log(cycle)
const doc = Nibs.optimize(cycle)
console.log(inspect(doc, true, 3, true))
const encoded = Nibs.encode(doc)
console.log(Buffer.from(encoded).toString('hex'))
const decoded = Nibs.decode(encoded)
console.log(decoded)
decoded[4]
console.log(decoded)
decoded[4].get('cycle')
console.log(decoded)
decoded[3]
console.log(decoded)

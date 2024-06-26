import { inspect } from 'node:util'
import { xxh64 } from "./xxhash64.js"
import { isRef, isScope, isIndexed } from "./symbols.js"

const ZIGZAG = 0
const FLOAT = 1
const SIMPLE = 2
const REF = 3
const BYTES = 8
const UTF8 = 9
const HEXSTRING = 10
const LIST = 11
const MAP = 12
const ARRAY = 13
const TRIE = 14
const SCOPE = 15
const FALSE = 0
const TRUE = 1
const NULL = 2

/**
 * @param {bigint} num
 * @returns {bigint}
 */
function bigzigzagEncode(num) {
    return num < 0 ? num * -2n - 1n : num * 2n
}

/**
 *
 * @param {number} small
 * @param {number|bigint} big
 * @returns {[number,...any]}
 */
function encodePair(small, big) {
    small |= 0
    const high = (small & 0xf) << 4
    if (big < 12) {
        big = Number(big) | 0
        return [1, high | big]
    }
    if (big < 0x100) {
        big = Number(big) | 0
        return [2, high | 12, big]
    }
    if (big < 0x10000) {
        big = Number(big) | 0
        return [3, high | 13, big & 0xff, big >>> 8]
    }
    if (big < 0x100000000) {
        big = Number(big) >>> 0
        const view = new DataView(new ArrayBuffer(4))
        view.setUint32(0, Number(big), true)
        return [5, high | 14, view.buffer]
    }
    const view = new DataView(new ArrayBuffer(8))
    view.setBigUint64(0, BigInt(big), true)
    return [9, high | 15, view.buffer]
}

/**
 * @param {number} num
 * @returns {[number,...any]}
 */
function encodeFloat(num) {
    const view = new DataView(new ArrayBuffer(8))
    view.setFloat64(0, num, true)
    return [9, (FLOAT << 4) | 15, view.buffer]
}

/**
 * @param {any} val
 * @returns {Uint8Array}
 */
export function encode(val) {
    const [size, ...parts] = encodeAny(val)
    return flatten(size, parts)
}

/**
 * @param {number} size
 * @param {any} parts
 * @returns {Uint8Array}
 */
function flatten(size, parts) {
    const out = new Uint8Array(size)
    let i = 0
    process(parts)
    if (i !== size) {
        console.log({ i, size, parts })
        throw new Error("Encoding error")
    }
    return out

    function process(v) {
        if (typeof (v) === "number") {
            out[i++] = v
        } else if (ArrayBuffer.isView(v)) {
            out.set(new Uint8Array(v.buffer, v.byteOffset, v.byteLength), i)
            i += v.byteLength
        } else if (Array.isArray(v)) {
            for (const s of v) {
                process(s)
            }
        } else if (v instanceof ArrayBuffer) {
            out.set(new Uint8Array(v), i)
            i += v.byteLength
        }
    }
}

/**
 * @param {string} val hex string
 * @returns {Uint8Array} bytes
 */
function hexDecode(val) {
    const byteLength = val.length >> 1
    const arr = new Uint8Array(byteLength)
    let j = 0
    for (let i = 0, l = val.length; i < l; i += 2) {
        arr[j++] = parseInt(val.substring(i, i + 2), 16)
    }
    return arr
}

/**
 * @param {ArrayBufferView|ArrayBuffer} val
 * @param {number} type
 * @returns {[number,...any]}
 */
function encodeBinary(val, type = BYTES) {
    const [len, ...pair] = encodePair(type, val.byteLength)
    return [len + val.byteLength, ...pair, val]
}

/**
 * @param {any[]} val
 * @returns {[number,...any]}
 */
function encodeList(val) {
    let totalLen = 0
    const parts = []
    for (const part of val) {
        if (val === undefined) continue
        const [subLen, ...subparts] = encodeAny(part)
        totalLen += subLen
        parts.push(...subparts)
    }
    const [len, ...pair] = encodePair(LIST, totalLen)
    return [len + totalLen, ...pair, ...parts]
}

/**
 * @param {any[]} val
 * @returns {[number,...any]}
 */
function encodeScope(val) {
    let totalLen = 0
    const parts = []
    const offsets = []
    let last = 0

    const [valueLen, ...valueParts] = encodeAny(val[0])

    for (let i = 1, l = val.length; i < l; i++) {
        const part = val[i]
        const [subLen, ...subparts] = encodeAny(part)
        offsets.push(totalLen)
        last = totalLen
        totalLen += subLen
        parts.push(...subparts)
    }

    // Generate index for ARRAY
    let width, index
    if (last < 0x100) {
        width = 1
        index = new Uint8Array(offsets)
    } else if (last < 0x10000) {
        width = 2
        index = new Uint16Array(offsets)
    } else if (last < 0x100000000) {
        width = 4
        index = new Uint32Array(offsets)
    } else {
        width = 8
        index = new BigUint64Array(offsets.map(num => BigInt(num)))
    }

    const [indexLen, ...indexPair] = encodePair(width, index.byteLength)
    totalLen += valueLen + indexLen + index.byteLength

    const [len, ...pair] = encodePair(SCOPE, totalLen)
    return [len + totalLen, ...pair, ...valueParts, ...indexPair, index, ...parts]
}

/**
 * @param {any[]} val
 * @returns {[number,...any]}
 */
function encodeArray(val) {
    let totalLen = 0
    const parts = []
    const offsets = []
    let last = 0
    for (const part of val) {
        if (val === undefined) continue
        const [subLen, ...subparts] = encodeAny(part)
        offsets.push(totalLen)
        last = totalLen
        totalLen += subLen
        parts.push(...subparts)
    }

    // Generate index for ARRAY
    let width, index
    if (last < 0x100) {
        width = 1
        index = new Uint8Array(offsets)
    } else if (last < 0x10000) {
        width = 2
        index = new Uint16Array(offsets)
    } else if (last < 0x100000000) {
        width = 4
        index = new Uint32Array(offsets)
    } else {
        width = 8
        index = new BigUint64Array(offsets.map(num => BigInt(num)))
    }

    const [indexLen, ...indexPair] = encodePair(width, index.byteLength)
    totalLen += indexLen + index.byteLength

    const [len, ...pair] = encodePair(ARRAY, totalLen)
    return [len + totalLen, ...pair, ...indexPair, index, ...parts]
}

/**
 * @param {Map<any,any>} val
 * @returns {[number,...any]}
 */
function encodeMap(val) {
    let totalLen = 0
    const parts = []
    for (let [key, value] of val) {
        if (value === undefined) continue
        const [keyLen, ...keyparts] = encodeAny(key)
        const encodedKey = flatten(keyLen, keyparts)
        parts.push(encodedKey)
        totalLen += keyLen
        const [valueLen, ...valueparts] = encodeAny(value)
        totalLen += valueLen
        parts.push(...valueparts)
    }
    const [len, ...pair] = encodePair(MAP, totalLen)
    return [len + totalLen, ...pair, ...parts]
}

/**
 * @param {Map<any,any>} val
 * @returns {[number,...any]}
 */
function encodeTrie(val) {
    let totalLen = 0
    /** @type {Map<Uint8Array,number>} */
    const offsets = new Map()
    const parts = []
    let last = 0
    for (const [key, value] of val) {
        if (value === undefined) continue
        last = totalLen
        const [keyLen, ...keyparts] = encodeAny(key)
        const encodedKey = flatten(keyLen, keyparts)
        parts.push(encodedKey)
        offsets.set(encodedKey, totalLen)
        totalLen += keyLen
        const [valueLen, ...valueparts] = encodeAny(value)
        totalLen += valueLen
        parts.push(...valueparts)
    }

    const { count, width, index } = encodeHamt(offsets)

    totalLen += count * width

    const [plen, ...pparts] = encodePair(width, count)
    totalLen += plen

    const [len, ...pair] = encodePair(TRIE, totalLen)

    return [len + totalLen, [...pair, ...pparts, index, ...parts]]

}

class TriePointer {
    /**
     * @param {bigint} hash
     * @param {number} target
     */
    constructor(hash, target) {
        this.hash = hash
        this.target = target
    }
}

class TrieNode {
    /**
     * @param {number} power bits for each path segment
     */
    constructor(power) {
        this.power = power
    }

    /**
     * @param {TriePointer} pointer
     * @param {number} depth
     * @returns {number} nodes created
     */
    insert(pointer, depth) {
        const segment = Number((pointer.hash >> BigInt(depth * this.power)) & BigInt((1 << this.power) - 1))
        /** @type {TrieNode|TriePointer|undefined} */
        const existing = this[segment]
        if (existing) {
            if (existing instanceof TrieNode) {
                return existing.insert(pointer, depth + 1)
            } else if (existing instanceof TriePointer) {

                const child = new TrieNode(this.power)
                this[segment] = child
                return 1 + child.insert(existing, depth + 1)
                    + child.insert(pointer, depth + 1)
            }
            throw new TypeError("Unknown type")
        }
        this[segment] = pointer
        return 1
    }

    /**
     * @param {(word?:number)=>number} write
     * @returns {number|undefined}
     */
    serialize(write) {
        // Serialize subnodes first
        const targets = {}
        const top = (1 << this.power) - 1
        for (let i = top; i >= 0; i--) {
            /** @type {TriePointer|TrieNode|undefined} */
            const entry = this[i]
            if (entry && entry instanceof TrieNode) {
                const serialized = entry.serialize(write)
                if (!serialized) return
                targets[i] = serialized
            }
        }
        const high = 1 << ((1 << this.power) - 1)

        let bitfield = 0
        let current = write()
        // Write our own table now
        for (let i = top; i >= 0; i--) {
            /** @type {TriePointer|TrieNode|undefined} */
            const entry = this[i]
            if (!entry) continue
            bitfield |= 1 << i
            if (entry instanceof TrieNode) {
                const offset = current - targets[i]
                if (offset >= high) return // overflow
                current = write(offset)
            } else if (entry instanceof TriePointer) {
                const target = entry.target
                if (target >= high) return // overflow
                current = write(high | target)
            }
        }
        return write(bitfield)
    }
}

/**
 * @param {Map<Uint8Array,number>} map
 * @param {number} optimize
 * @returns {{count:number,width:number,index:Uint8Array|Uint16Array|Uint32Array|BigUint64Array}}
*/
function encodeHamt(map, optimize = -1) {
    // Calculate largest output target...
    let maxTarget = 0
    let count = 0
    for (const v of map.values()) {
        count++
        maxTarget = Math.max(maxTarget, v)
    }

    // ... and use that for the smallest possible start power that works
    let startPower = maxTarget < 0x100 ? 3 :
        maxTarget < 0x10000 ? 4 :
            maxTarget < 0x100000000 ? 5 : 6

    // Try to set a sane default optimization level if not specified
    if (optimize === -1) {
        optimize = Math.max(2, Math.min(255, 1000 / (count * count)))
    }

    // Try several combinations of parameters to find the smallest encoding.
    let win = null
    // The size of the currently winning index
    let min = 1 / 0
    // Brute force all hash seeds in the 8-bit keyspace.
    for (let seed = 0; seed <= optimize; seed++) {
        // Precompute the hashes outside of the bitsize loop to save CPU.
        const hashes = new Map()
        for (const k of map.keys()) {
            hashes.set(k, xxh64(k, BigInt(seed)))
        }
        // Try bit sizes small first and break of first successful encoding.
        for (let power = startPower; power <= 6; power++) {

            // Create a new Trie and insert the data
            const trie = new TrieNode(power)
            // Count number of rows in the index
            let count = 1
            for (const [k, v] of map.entries()) {
                const hash = hashes.get(k)
                count += trie.insert(new TriePointer(hash, v), 0)
            }

            // Reserve a slot for the seed
            count++

            // Width of pointers in bytes
            const width = 1 << (power - 3)
            // Total byte size of index if generated
            const size = count * width

            // Abort if the size is not smaller than the current winner
            if (size >= min) continue

            const index =
                power === 3 ? new Uint8Array(count) :
                    power === 4 ? new Uint16Array(count) :
                        power === 5 ? new Uint32Array(count) :
                            new BigUint64Array(count)

            let i = 0
            /** @type {(word?:number)=>number} */
            const write = word => {
                if (word !== undefined) {
                    i++
                    if (index instanceof BigUint64Array) {
                        index[count - i] = BigInt(word)
                    } else {
                        index[count - i] = word
                    }
                }
                return (i - 1) * width
            }

            const success = trie.serialize(write)
            write(seed)
            if (typeof (success) === 'number') {
                min = size
                win = { count, width, index }
                break
            }
        }
    }
    if (!win) throw new Error("There was no winner")
    return win
}

/**
 * @param {any} val
 * @returns {[number,...any]}
 */
function encodeAny(val) {
    const type = typeof (val)
    if (type === "number") {
        if (val !== val || val === Infinity || val === -Infinity || Math.floor(val) !== val) {
            return encodeFloat(val)
        }
        return encodePair(ZIGZAG, bigzigzagEncode(BigInt(val)))
    }
    if (type === "bigint") {
        return encodePair(ZIGZAG, bigzigzagEncode(val))
    }
    if (type == "string") {
        if (/^(?:[0-9a-f][0-9a-f])+$/.test(val)) {
            return encodeBinary(hexDecode(val), HEXSTRING)
        }
        return encodeBinary(new TextEncoder().encode(val), UTF8)
    }
    if (type === "boolean") {
        return encodePair(SIMPLE, val ? TRUE : FALSE)
    }
    if (val === null) {
        return encodePair(SIMPLE, NULL)
    }
    if (type === "object") {
        if (ArrayBuffer.isView(val) || val instanceof ArrayBuffer) {
            return encodeBinary(val)
        }
        if (Array.isArray(val)) {
            if (val[isScope]) {
                return encodeScope(val)
            }
            if (val[isIndexed]) {
                return encodeArray(val)
            }
            return encodeList(val)
        }
        if (val instanceof Map) {
            if (val[isIndexed]) {
                return encodeTrie(val)
            }
            return encodeMap(val)
        }
        if (typeof (val[isRef]) === 'number') {
            return encodePair(REF, val[isRef])
        }
        if (val[isIndexed]) {
            return encodeTrie(new Map(Object.entries(val)))
        }
        return encodeMap(new Map(Object.entries(val)))
    }
    console.error({unexpected_value: val})
    throw new TypeError("Unsupported type " + typeof(val))
}

/**
 * @param {Uint8Array} buf
 * @returns {any}
 */
export function decode(buf) {
    const data = new DataView(buf.buffer, buf.byteOffset, buf.byteLength)
    const [value, offset] = decodeAny(data, 0, -1)
    if (offset !== data.byteLength) throw new Error("Extra data in intput")
    return value
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @returns {{little:number,big:number|bigint,newoffset:number}}
 */
function decodePair(data, offset) {
    const head = data.getUint8(offset++)
    const little = head >> 4
    const big = head & 0xf
    switch (big) {
        case 0xc:
            return { little, big: data.getUint8(offset), newoffset: offset + 1 }
        case 0xd:
            return { little, big: data.getUint16(offset, true), newoffset: offset + 2 }
        case 0xe:
            return { little, big: data.getUint32(offset, true), newoffset: offset + 4 }
        case 0xf:
            return { little, big: data.getBigUint64(offset, true), newoffset: offset + 8 }
    }
    return { little, big, newoffset: offset }
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @returns {number}
 */
function skip(data, offset) {
    const { little, big, newoffset } = decodePair(data, offset)
    return little <= 8 ? newoffset : newoffset + Number(big)
}

/**
 * @param {number|bigint} num
 * @returns {number|bigint}
 */
function decodeZigZag(num) {
    num = BigInt(num)
    num = (num >> 1n) ^ (-(num & 1n))
    // Return as normal number when safe
    return num <= Number.MAX_SAFE_INTEGER && num >= Number.MIN_SAFE_INTEGER ?
        Number(num) : num
}

/**
 * @param {number|bigint} num
 * @returns {number}
 */
function decodeFloat(num) {
    const converter = new DataView(new ArrayBuffer(8))
    converter.setBigUint64(0, BigInt(num), true)
    return converter.getFloat64(0, true)
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @param {number} width
 * @returns {number|bigint}
 */
function decodePointer(data, offset, width) {
    switch (width) {
        case 1: return data.getUint8(offset)
        case 2: return data.getUint16(offset, true)
        case 4: return data.getUint32(offset, true)
        case 8: return data.getBigUint64(offset, true)
    }
    throw new Error("Invalid width")
}

/** @typedef {{refs:any[],offset:number}} RefScope */

/**
 * @param {DataView} data
 * @param {RefScope} scope
 * @param {number} id
 * @returns {any}
 */
function decodeRef(data, scope, id) {
    let cached = scope.refs[id]
    if (cached) return cached.value
    scope.refs[id] = cached = {}
    const { little: width, big: count, newoffset } = decodePair(data, scope.offset)
    const ptr = decodePointer(data, newoffset + id * width, width)
    const alpha = newoffset + Number(count) * width + Number(ptr)
    const [value, omega] = decodeAny(data, alpha, scope)
    cached.value = value
    return value
}

/**
 * @param {DataView} data
 * @param {number} alpha
 * @param {number} len
 * @returns {[Uint8Array, number]}
 */
function decodeBytes(data, alpha, len) {
    return [new Uint8Array(data.buffer, data.byteOffset + alpha, len), alpha + len]
}

/**
 * @param {DataView} data
 * @param {number} alpha
 * @param {number} len
 * @returns {[string, number]}
 */
function decodeString(data, alpha, len) {
    const str = new TextDecoder().decode(new Uint8Array(data.buffer, data.byteOffset + alpha, len))
    return [str, alpha + len]
}

/**
 * @param {DataView} data
 * @param {number} alpha
 * @param {number} len
 * @returns {[string, number]}
 */
function decodeHexstring(data, alpha, len) {
    const buf = new Uint8Array(data.buffer, data.byteOffset + alpha, len)
    const hex = Array.prototype.map.call(buf, byte => byte.toString(16).padStart(2, '0')).join('')
    return [hex, alpha + len]
}

function makeLazy(obj, index, data, alpha, scope) {
    Object.defineProperty(obj, index, {
        configurable: true,
        enumerable: true,
        get: () => {
            const value = decodeAny(data, alpha, scope)[0]
            Object.defineProperty(obj, index, {
                writable: true,
                enumerable: true,
                value
            })
            return value
        }
    })
    return skip(data, alpha)
}

/**
 * @param {DataView} data
 * @param {number} alpha
 * @param {number} omega
 * @param {RefScope} scope
 * @returns {[any[], number]}
 */
function decodeList(data, alpha, omega, scope) {
    const list = []
    let i = 0
    while (alpha < omega) {
        alpha = makeLazy(list, i++, data, alpha, scope)
    }
    list.length = i
    if (alpha !== omega) throw new Error("Extra data in map/trie")
    return [list, omega]
}

/**
 * @param {DataView} data
 * @param {number} alpha
 * @param {number} omega
 * @param {RefScope} scope
 * @returns {[any[], number]}
 */
function decodeArray(data, alpha, omega, scope) {
    const { little, big, newoffset } = decodePair(data, alpha)
    alpha = newoffset + little * Number(big)
    const [list] = decodeList(data, alpha, omega, scope)
    Object.defineProperty(list, isIndexed, { value: true })
    return [list, omega]
}

const lazy = Symbol('lazy')

/**
 * @param {DataView} data
 * @param {number} alpha
 * @param {number} omega
 * @param {RefScope} scope
 * @returns {[Object<string,any>, number]}
 */
function decodeMap(data, alpha, omega, scope) {
    const map = {}

    while (alpha < omega) {
        const [key, index] = decodeAny(data, alpha, scope)
        Object.defineProperty(map, key, {
            get() {
                const [value] = decodeAny(data, index, scope)
                Object.defineProperty(map, key, {
                    value,
                    enumerable: true,
                })
                return value
            },
            enumerable: true,
            configurable: true,
        })

        alpha = skip(data, index)
    }
    if (alpha !== omega) throw new Error("Extra data in map/trie")

    return [map, omega]
}

/**
 * @param {DataView} data
 * @param {number} alpha
 * @param {number} omega
 * @param {RefScope} scope
 * @returns {[Object<string,any>, number]}
 */
function decodeTrie(data, alpha, omega, scope) {
    const { little, big, newoffset } = decodePair(data, alpha)
    alpha = newoffset + little * Number(big)
    const [map] = decodeMap(data, alpha, omega, scope)
    Object.defineProperty(map, isIndexed, { value: true })
    return [map, omega]
}

/**
 * @param {DataView} data
 * @param {number} alpha
 * @param {number} omega
 * @returns {[any, number]}
 */
function decodeScope(data, alpha, omega) {
    // Calculate offset after wrapped value
    // This is where the ref index starts with a nibs pair for width/count
    const offset = skip(data, alpha)
    const [value] = decodeAny(data, alpha, { refs: [], offset })
    // Return the wrapped value
    return [value, omega]
}

/**
 * @param {DataView} data
 * @param {number} alpha
 * @param {RefScope} scope
 * @returns {[any, number]} value and new offset
 */
function decodeAny(data, alpha, scope) {
    const { little, big, newoffset } = decodePair(data, alpha)
    alpha = newoffset
    switch (little) {
        case ZIGZAG:
            return [decodeZigZag(big), alpha]
        case FLOAT:
            return [decodeFloat(big), alpha]
        case SIMPLE:
            switch (big) {
                case FALSE: return [false, alpha]
                case TRUE: return [true, alpha]
                case NULL: return [null, alpha]
            }
            throw new Error("Invalid subtype")
        case REF:
            return [decodeRef(data, scope, Number(big)), alpha]
        case BYTES:
            return decodeBytes(data, alpha, Number(big))
        case UTF8:
            return decodeString(data, alpha, Number(big))
        case HEXSTRING:
            return decodeHexstring(data, alpha, Number(big))
        case LIST:
            return decodeList(data, alpha, alpha + Number(big), scope)
        case MAP:
            return decodeMap(data, alpha, alpha + Number(big), scope)
        case ARRAY:
            return decodeArray(data, alpha, alpha + Number(big), scope)
        case TRIE:
            return decodeTrie(data, alpha, alpha + Number(big), scope)
        case SCOPE:
            return decodeScope(data, alpha, alpha + Number(big))
    }
    throw new Error("Invalid type")
}

/**
 * @param {any} doc
 * @returns {Map<any,number>}
 */
function findRefs(doc) {

    // Wild guess, but real data with lots of dups over 1mb is 1 for reference
    let pointer_cost = 2
    const small_string = pointer_cost + 1
    const small_number = 1 << (pointer_cost << 3) - 1
    function potentiallyBig(val) {
        const t = typeof (val)
        if (t === "string") {
            return val.length > small_string
        } else if (t === "number") {
            return Math.floor(val) !== val || val <= -small_number || val > small_number
        }
        return false
    }

    const seen = new Map()
    const objects = new Map()

    /** @param {any} val */
    function walk(val) {
        if (!val) return
        if (typeof (val) !== 'object') {
            if (!potentiallyBig(val)) return
            let count = seen.get(val)
            if (count == undefined) {
                seen.set(val, 1)
            } else {
                seen.set(val, count + 1)
            }
            return
        }
        const objectSeen = objects.get(val)
        if (objects.get(val)) {
            const count = seen.get(val)
            if (count) {
                seen.set(val, count + 1)
            } else {
                seen.set(val, 2)
            }
            return
        }
        objects.set(val, true)
        if (Array.isArray(val)) {
            for (const v of val) {
                walk(v)
            }
        } else {
            const entries = val instanceof Map ? val.entries() : Object.entries(val)
            for (const [k, v] of entries) {
                walk(k)
                walk(v)
            }
        }
    }

    walk(doc)

    return new Map([...seen.entries()]
        .filter(([k, v]) => v > 1)
        .sort(([, v1], [, v2]) => v2 - v1)
        .map(([k], index) => [k, index])
    )
}

/**
 * @param {any} doc
 * @param {number} indexLimit Use indexes if count is at least this number
 * @param {Map<any,number>|undefined} refs Optional list of values to use as references.
 * @returns {any} but with optimizations
 */
export function optimize(doc, indexLimit = 12, refs = undefined, skipRefCheck = false) {
    if (!refs) {
        const found = findRefs(doc)
        doc = optimize(doc, indexLimit, found)
        if (found.size === 0) return doc
        const scope = [doc]
        for (const ref of found.keys()) {
            scope.push(optimize(ref, indexLimit, found, true))
        }
        Object.defineProperty(scope, isScope, { value: true })
        return scope
    }
    if (!skipRefCheck && refs.get(doc) !== undefined) {
        const ref = {}
        Object.defineProperty(ref, isRef, { value: refs.get(doc) })
        return ref
    }
    const t = typeof (doc)
    if (t !== "object" || !doc) return doc
    let count
    if (Array.isArray(doc)) {
        count = doc.length
        doc = doc.map(v => optimize(v, indexLimit, refs))
    } else {
        if (!(doc instanceof Map)) {
            doc = new Map(Object.entries(doc))
        }
        count = 0
        const copy = new Map()
        for (const [k, v] of doc.entries()) {
            copy.set(optimize(k, indexLimit, refs), optimize(v, indexLimit, refs))
            count++
        }
        doc = copy
    }
    if (count >= indexLimit) {
        Object.defineProperty(doc, isIndexed, { value: true })
    }
    return doc
}

// Convert Objects back to maps and assume integers are integers and boolean is boolean.
export function toMap(obj) {
    const map = new Map(Object.entries(obj).map(([k, v]) => [
        /^[0-9]+$/.test(k) ? parseInt(k, 10) :
            k === 'true' ? true :
                k === 'false' ? false : k, v
    ]))
    for (const sym of Object.getOwnPropertySymbols(obj)) {
        map[sym] = obj[sym]
    }
    return map
}

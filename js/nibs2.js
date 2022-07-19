import { xxh64 } from "./xxhash64.js"

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
 * @typedef {{index_limit:number,trie_seed:number,trie_optimize:number}} NibsEncodeConfig
 */

/** @type {NibsEncodeConfig} */
export const DEFAULTS = {
    index_limit: 32,
    trie_seed: 0,
    trie_optimize: 10,
}


/**
 * @param {number} num
 * @returns {number}
 */
function zigzagEncode(num) {
    return Math.abs(num * 2) - (num < 0 ? 1 : 0)
}

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
 * @param {NibsEncodeConfig} config?
 * @returns {Uint8Array}
 */
export function encode(val, config = DEFAULTS) {
    if (config !== DEFAULTS) {
        config = { ...DEFAULTS, ...config }
    }
    const [size, ...parts] = encodeAny(val, config)
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
 * @param {NibsEncodeConfig} config
 * @returns {[number,...any]}
 */
function encodeArray(val, config) {
    let totalLen = 0
    const parts = []
    const offsets = []
    let last = 0
    for (const part of val) {
        const [subLen, ...subparts] = encodeAny(part, config)
        offsets.push(totalLen)
        last = totalLen
        totalLen += subLen
        parts.push(...subparts)
    }

    if (offsets.length < config.index_limit) {
        const [len, ...pair] = encodePair(LIST, totalLen)
        return [len + totalLen, ...pair, ...parts]
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
        throw new Error("Array too big")
    }

    const [indexLen, ...indexPair] = encodePair(width, index.byteLength)
    totalLen += indexLen + index.byteLength

    const [len, ...pair] = encodePair(ARRAY, totalLen)
    return [len + totalLen, ...pair, ...indexPair, index, ...parts]
}

/**
 * @param {Map<any,any>} val
 * @param {NibsEncodeConfig} config
 * @returns {[number,...any]}
 */
function encodeMap(val, config) {
    let totalLen = 0
    const offsets = new Map()
    const parts = []
    let last = 0
    for (const [key, value] of val) {
        last = totalLen
        const [keyLen, ...keyparts] = encodeAny(key, config)
        const encodedKey = flatten(keyLen, keyparts)
        parts.push(encodedKey)
        offsets.set(encodedKey, totalLen)
        totalLen += keyLen
        const [valueLen, ...valueparts] = encodeAny(value, config)
        totalLen += valueLen
        parts.push(...valueparts)
    }
    if (offsets.size < config.index_limit) {
        const [len, ...pair] = encodePair(MAP, totalLen)
        return [len + totalLen, ...pair, ...parts]
    }

    let seed = config.trie_seed
    const optimize = config.trie_optimize

    console.log({ offsets, seed, optimize })

    /** @type {Uint8ArrayConstructor|Uint16ArrayConstructor|Uint32ArrayConstructor} ArrayBufferView constructor */
    let IntArray
    /** @type {number} */
    let bits
    if (last < 0x80) {
        IntArray = Uint8Array
        bits = 3
    } else if (last < 0x8000) {
        IntArray = Uint16Array
        bits = 4
    } else if (last < 0x80000000) {
        IntArray = Uint32Array
        bits = 5
    } else {
        throw new Error("Trie too big")
    }

    const width = 1 << (bits - 3)
    const mod = 1 << (width * 8)

    let win, min = 0, ss = seed
    for (let i = 0; i <= optimize; i++) {
        const s = (seed + i) % mod
        const [potentialTrie, count] = build_trie(offsets, bits, BigInt(s))
        if (!win || count < min) {
            win = potentialTrie
            min = count
            ss = s
        }
    }
    const trie = win
    seed = ss


    let height = 0
    const trieParts = []

    console.log({ trie, seed })
    write_node(trie)

    function write_node(node) {
        // Sort highest first since we're writing backwards
        const segments = Object.keys(node).sort((a, b) => a < b ? 1 : a > b ? -1 : 0)
        console.log({ segments })

        // Calculate the target addresses
        const targets = {}
        for (const k of segments) {
            const v = node[k]
            console.log({ v })
        }
        // for i, k in ipairs(segments) do
        //     local v = node[k]
        //     if type(v[2]) == "number" then
        // targets[i] = -1 - v[2]
        //     else
        // targets[i] = height
        // write_node(v)
        // end
        // end

        // Generate the pointers
        let bitfield = 0
        // for i, k in ipairs(segments) do
        //     bitfield = bor(bitfield, lshift(1, k))
        //     local target = targets[i]
        //     if target >= 0 then
        //         target = height - target - width
        //     end
        //     -- p(height, { segment = k, pointer = target })
        //     table.insert(parts, target)
        //     height = height + width
        // end

        trieParts.push(bitfield)
        height += width

    }

    console.log({ trieParts })
    trieParts.push(seed)
    const count = trieParts.length
    const trieIndex = new IntArray(trieParts.reverse())

    console.log({ trieIndex })

    const [indexLen, ...indexPair] = encodePair(width, trieIndex.byteLength)
    totalLen += indexLen + trieIndex.byteLength

    const [len, ...pair] = encodePair(TRIE, totalLen)
    return [len + totalLen, ...pair, ...indexPair, trieIndex, ...parts]

}

// -- p { parts = parts }
// table.insert(parts, seed)
// local count = #parts
// local slice = Slice(count)
// for i, part in ipairs(parts) do
//     slice[count - i] = part
// end

// local index_width = count * width
// assert(sizeof(slice) == index_width)

// local more, head = encode_pair(width, index_width)
// return more + index_width, { head, slice }



/**
 * @param {Map<Uint8Array,number>} offsets
 * @param {number} bits
 * @param {bigint} seed
 * @returns {[any,number]}
 */
function build_trie(offsets, bits, seed) {
    const mask = (1 << bits) - 1
    /** @type {{hash?:bigint,offset?:number}}} */
    const trie = {}
    let count = 0

    // Insert the offsets into the trie
    for (const [key, offset] of offsets.entries()) {
        const hash = xxh64(key, seed)
        let o = 0
        let node = trie
        while (o < 64) {
            if (node.hash) {
                // If the node already has data, move it down one
                const hash = node.hash
                const offset = node.offset
                delete node.hash
                delete node.offset
                node[Number(hash / BigInt(1 << o)) & mask] = { hash, offset }
                count++
                // And try again
            } else {
                if (node !== trie && Object.keys(node).length === 0) {
                    // Otherwise, check if node is empty
                    // and claim it
                    node.hash = hash
                    node.offset = offset
                    break
                }
                // Or follow/create the next in the path
                const segment = Number(hash / BigInt(1 << o)) & mask
                let next = node[segment]
                if (next) {
                    node = next
                } else {
                    next = {}
                    count++
                    node[segment] = next
                    node = next
                }
                o += bits
            }
        }
    }
    return [trie, count]
}

/**
 * @param {any} val
 * @param {NibsEncodeConfig} config
 * @returns {[number,...any]}
 */
export function encodeAny(val, config) {
    const type = typeof (val)
    if (type === "number") {
        if (val !== val || val === Infinity || val === -Infinity || Math.floor(val) !== val) {
            return encodeFloat(val)
        }
        return encodePair(ZIGZAG, zigzagEncode(val))
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
            return encodeArray(val, config)
        }
        if (val instanceof Map) {
            return encodeMap(val, config)
        }
        return encodeMap(new Map(Object.entries(val)), config)
    }
    throw "TODO, encode more types"
}
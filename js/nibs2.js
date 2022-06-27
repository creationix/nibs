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

function zigzagEncode(num) {
    return Math.abs(num * 2) - (num < 0 ? 1 : 0)
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
    /**@type {[number,...any]} */
    const [size, ...parts] = encodeAny(val)
    // console.log({ size, parts })
    const out = new Uint8Array(size)
    let i = 0
    flatten(parts)
    if (i !== size) {
        console.log({ i, size, parts })
        throw new Error("Encoding error")
    }
    return out

    function flatten(v) {
        if (typeof (v) === "number") {
            out[i++] = v
        } else if (ArrayBuffer.isView(v)) {
            out.set(new Uint8Array(v.buffer, v.byteOffset, v.byteLength), i)
            i += v.byteLength
        } else if (Array.isArray(v)) {
            for (const s of v) {
                flatten(s)
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
function encodeArray(val) {
    let totalLen = 0
    const parts = []
    for (const part of val) {
        const [subLen, ...subparts] = encodeAny(part)
        totalLen += subLen
        parts.push(...subparts)
    }
    const [len, ...pair] = encodePair(LIST, totalLen)
    return [len + totalLen, ...pair, ...parts]
}

/**
 * @param {Record<string,any} val 
 * @returns {[number,...any]}
 */
function encodeObject(val) {
    console.log({ val })
    throw "TODO encode object"

}

function encodeMap(val) {
    console.log({ val })
    let totalLen = 0
    const parts = []
    for (const [key, value] of val) {
        const [keyLen, ...keyparts] = encodeAny(key)
        totalLen += keyLen
        parts.push(...keyparts)
        const [valueLen, ...valueparts] = encodeAny(value)
        totalLen += valueLen
        parts.push(...valueparts)
    }
    const [len, ...pair] = encodePair(MAP, totalLen)
    return [len + totalLen, ...pair, ...parts]
}

/**
 * @param {any} val 
 * @returns {[number,...any]}
 */
export function encodeAny(val) {
    const type = typeof (val)
    if (type === "number") {
        if (val !== val || val === Infinity || val === -Infinity || Math.floor(val) !== val) {
            return encodeFloat(val)
        }
        return encodePair(ZIGZAG, zigzagEncode(val))
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
            return encodeArray(val)
        }
        if (val instanceof Map) {
            return encodeMap(val)
        }
        return encodeObject(val)
    }
    throw "TODO, encode more types"
}
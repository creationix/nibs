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

function zigzagEncode(num) {
    return Math.abs(num * 2) - (num < 0 ? 1 : 0)
}

function encodePair(small, big) {
    small |= 0
    const high = (small & 0xf) << 4
    if (big < 12) {
        return high | big
    }
    if (big < 0x100) {
        big |= 0
        return [
            high | 0xc,
            big,
        ]
    }
    if (big < 0x10000) {
        big |= 0
        return [
            high | 0xd,
            big & 0xff,
            big >>> 8,
        ]
    }
    if (big < 0x100000000) {
        big >>>= 0
        return [
            high | 0xe,
            big & 0xff,
            (big >>> 8) & 0xff,
            (big >>> 16) & 0xff,
            big >>> 24,
        ]
    }
    if (big < 0x20000000000000) {
        return [
            high | 0xf,
            big & 0xff,
            (big >>> 8) & 0xff,
            (big >>> 16) & 0xff,
            (big >>> 24) & 0xff,
            (big >>> 32) & 0xff,
            (big >>> 40) & 0xff,
            (big >>> 48) & 0xff,
            big >>> 56,
        ]
    }
    throw new Error("TODO: big numbers")
}

/**
 * @param {any} val 
 * @returns {Uint8Array}
 */
export function encode(val) {
    const parts = encodeAny(val)
    console.log({ parts })
    const size = count(parts)
    const out = new Uint8Array(size)
    let i = 0
    flatten(parts)
    if (i !== size) throw new Error("Encoding error")
    return out

    function count(v) {
        if (typeof (v) === "number") return 1
        if (Array.isArray(v)) {
            let sum = 0
            for (const s of v) {
                sum += count(s)
            }
            return sum
        }
        throw "TODO count more types"
    }

    function flatten(v) {
        if (typeof (v) === "number") {
            out[i++] = v
        } else if (Array.isArray(v)) {
            for (const s of v) {
                flatten(s)
            }
        } else {
            throw "TODO flatten more types"
        }
    }
}

export function encodeAny(val) {
    if (typeof (val) === "number") {
        return encodePair(ZIGZAG, zigzagEncode(val))
    }
    throw "TODO"
}
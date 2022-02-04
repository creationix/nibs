/**
 * @param {Uint8Array|string} input
 */
export function decode(input) {
    if (typeof input === "string") {
        input = new TextEncoder().encode(input)
    }
    return decodeAny(new DataView(input.buffer, input.byteOffset, input.byteLength), 0);
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @returns {{little:number,big:number|bigint,len:number}}
 */
function decodePair(data, offset) {
    const head = data.getUint8(offset++)
    const little = head >> 4
    const big = head & 0xf
    switch (big) {
        case 0xc:
            return { little, big: data.getUint8(offset), len: 2 }
        case 0xd:
            return { little, big: data.getUint16(offset, true), len: 3 }
        case 0xe:
            return { little, big: data.getUint32(offset, true), len: 5 }
        case 0xf:
            return { little, big: data.getBigUint64(offset, true), len: 9 }
    }
    return { little, big, len: 1 }
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @returns {number|boolean|null|Uint8Array|string|array|object}
 */
function decodeAny(data, offset) {
    const { little, big, len } = decodePair(data, offset)
    switch (little) {
        case 0: // Integer
            return big
        case 1: // NegInteger
            return -big
        case 2: // FloatingPoint
            return decodeFloat(BigInt(big))
        case 3: // Simple
            switch (big) {
                case 0: // false
                    return false
                case 1: // true
                    return true
                case 2: // null
                    return null
                case 3: // NaN
                    return NaN
                case 4: // Infinity
                    return Infinity
                case 5: // -Infinity
                    return -Infinity
            }
            throw new Error("Unexpected nibs simple subtype: " + big)
        case 4: // Binary
            return new Uint8Array(data.buffer, data.byteOffset + offset + len, Number(big))
        case 5: // String
            return new TextDecoder().decode(new Uint8Array(data.buffer, data.byteOffset + offset + len, Number(big)))
        case 6: // List
            return lazyList(data.buffer, data.byteOffset + offset + len, Number(big))
        case 7: // Map
            return lazyMap(data.buffer, data.byteOffset + offset + len, Number(big))
    }
    throw new Error("Unexpected nibs type: " + little)
}

/**
 * Get the total size of a value in bytes.
 * Useful for skipping a value.
 * @param {DataView} data
 * @param {number} offset
 * @returns {number}
 */
function size(data, offset) {
    const h = decodePair(data, offset)
    const { little, big, len } = h
    if (little < 4) {
        return len
    }
    if (little < 15) {
        return len + big
    }
    return len + size(data, offset + len)
}

///////////////////////////////////////////////////////////////////////////

/**
 * @param {ArrayBuffer} buffer
 * @param {number} byteOffset
 * @param {number} byteLength
 */
function lazyMap(buffer, byteOffset, byteLength) {
    const data = new DataView(buffer, byteOffset, byteLength)
    let offset = 0
    const obj = {}
    while (offset < data.byteLength) {
        const key = decodeAny(data, offset)
        offset += size(data, offset)
        const current = offset
        Object.defineProperty(obj, key, {
            get() {
                const value = decodeAny(data, current)
                Object.defineProperty(obj, key, { value })
                return value
            },
            enumerable: true,
            configurable: true,
        })
        offset += size(data, offset)
    }
    return obj
}

/**
 * @param {ArrayBuffer} buffer
 * @param {number} byteOffset
 * @param {number} byteLength
 */
function lazyList(buffer, byteOffset, byteLength) {
    const data = new DataView(buffer, byteOffset, byteLength)
    let offset = 0
    const arr = []
    let i = 0
    while (offset < data.byteLength) {
        const current = offset
        const index = i++
        Object.defineProperty(arr, index, {
            get() {
                const value = decodeAny(data, current)
                Object.defineProperty(arr, index, {
                    value
                })
                return value
            },
            enumerable: true,
            configurable: true,
        })
        offset += size(data, offset)
    }
    arr.length = i
    return arr
}

///////////////////////////////////////////////////////////////////////////

/**
 * Calculate number of bytes needed to encode pair based on big value.
 * @param {number} big number to encode up to 64bits
 * @returns number of bytes needed
 */
function sizePair(big) {
    return (big < 0xc) ? 1
        : (big < 0x100) ? 2
            : (big < 0x10000) ? 3
                : (big < 0x100000000) ? 5
                    : 9
}

/**
 * Calculate number of bytes needed to store a list
 * @param {any[]} list
 * @returns number of bytes needed
 */
function sizeArray(list) {
    let total = 0
    for (const item of list) {
        total += sizeAny(item)
    }
    return sizePair(total) + total
}

/**
 * Calculate number of bytes needed to store a map
 * @param {Record<string,any>} map
 * @returns number of bytes needed
 */
function sizeObject(map) {
    let total = 0
    for (const key in map) {
        total += sizeAny(key)
        total += sizeAny(map[key])
    }
    return sizePair(total) + total
}

/**
 * @param {any} val
 * @returns number of bytes needed
 */
function sizeAny(val) {
    const type = typeof val
    switch (type) {
        case "number":
            if (val === Infinity || val === -Infinity || isNaN(val)) {
                return 1
            }
            if (val === Math.floor(val)) {
                return sizePair(Math.abs(val))
            }
            return sizePair(encodeFloat(val))
        case "string":
            // TODO: see if there is a faster way to get this length.
            const len = (new TextEncoder().encode(val)).byteLength
            return sizePair(len) + len
        case "boolean":
            return 1
        case "object":
            if (val === null)
                return 1
            if (ArrayBuffer.isView(val))
                return sizePair(val.byteLength) + val.byteLength
            if (Array.isArray(val))
                return sizeArray(val)
            return sizeObject(val)
    }
    throw new TypeError("Unsupported type " + type)
}

export function encode(val) {
    const state = { len: 0 }
    const parts = encodeAny(state, val)
    const data = new DataView(new ArrayBuffer(state.len))
    const buf = new Uint8Array(data.buffer)
    let offset = 0;
    write(parts)
    /**
     * @param {number|ArrayBuffer|ArrayBufferView|(number|ArrayBuffer|ArrayBufferView)[]} v
     */
    function write(v) {
        if (typeof v === "number") {
            data.setUint8(offset++, v)
        } else if (Array.isArray(v)) {
            for (const i of v) {
                write(i)
            }
        } else if (v instanceof ArrayBuffer) {
            buf.set(new Uint8Array(v), offset)
            offset += v.byteLength
        } else if (ArrayBuffer.isView(v)) {
            const b = new Uint8Array(v.buffer, v.byteOffset, v.byteLength)
            buf.set(b, offset)
            offset += v.byteLength
        } else {
            throw new TypeError("Unexpected data in results " + typeof v)
        }
    }
    return buf
}

const converter = new DataView(new ArrayBuffer(8))

/**
 * @param {number} val
 * @returns {bigint}
 */
function encodeFloat(val) {
    converter.setFloat64(0, val, true)
    return converter.getBigUint64(0, true)
}

/**
 * @param {bigint} val
 * @returns {number}
 */
function decodeFloat(val) {
    converter.setBigUint64(0, val, true)
    return converter.getFloat64(0, true)
}

/**
 * @param {len:number} state
 * @param {any} val
 */
function encodeAny(state, val) {
    const type = typeof val
    switch (type) {
        case "number":
            if (isNaN(val))
                return encodePair(state, 3, 3)
            if (val === Infinity)
                return encodePair(state, 3, 4)
            if (val === -Infinity)
                return encodePair(state, 3, 5)
            if (val === Math.floor(val)) {
                if (val >= 0) {
                    return encodePair(state, 0, val)
                } else {
                    return encodePair(state, 1, -val)
                }
            }
            return encodePair(state, 2, encodeFloat(val))
        case "boolean":
            return encodePair(state, 3, val ? 1 : 0)
        case "object":
            if (val === null)
                return encodePair(state, 3, 2)
            if (ArrayBuffer.isView(val))
                return encodeBinary(state, val)
            if (Array.isArray(val))
                return encodeArray(state, val)
            return encodeObject(state, val)
        case "string":
            return encodeString(state, val)
    }
    throw new TypeError("Unsupported type " + type)
}

/**
 * @param {{len:number}} state
 * @param {string} str
 */
function encodeString(state, str) {
    return encodeBinary(state, new TextEncoder().encode(str), 5)
}

/**
 * @param {{len:number}} state
 * @param {ArrayBufferView} buf
 * @param {number} small?
 */
function encodeBinary(state, buf, small = 4) {
    state.len += buf.byteLength
    return [
        encodePair(state, small, buf.byteLength),
        new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength)
    ]
}

/**
 * @param {{len:number}} state
 * @param {any[]} list
 */
function encodeArray(state, list) {
    const start = state.len
    const parts = []
    for (const item of list) {
        parts.push(encodeAny(state, item))
    }
    const len = state.len - start
    parts.unshift(encodePair(state, 6, len))
    return parts.flat()
}

/**
 * @param {{len:number}} state
 * @param {Record<string,any>} map
 */
function encodeObject(state, map) {
    const start = state.len
    const parts = []
    for (const key in map) {
        parts.push(encodeAny(state, key))
        parts.push(encodeAny(state, map[key]))
    }
    const len = state.len - start
    parts.unshift(encodePair(state, 7, len))
    return parts.flat()
}

/**
 * @param {{len:number}} state
 * @param {number} small u4 sized number to encode
 * @param {number|bigint} big up to u64 sized number to encode
 */
function encodePair(state, small, big) {
    const high = small << 4
    if (big < 0xc) {
        state.len++
        return high | Number(big)
    } else if (big < 0x100) {
        state.len += 2
        return [high | 12, Number(big)]
    } else if (big < 0x10000) {
        state.len += 3
        const view = new DataView(new ArrayBuffer(2))
        view.setUint16(0, Number(big), true)
        return [high | 13, view.buffer]
    } else if (big < 0x100000000) {
        state.len += 5
        const view = new DataView(new ArrayBuffer(4))
        view.setUint32(0, Number(big), true)
        return [high | 14, view.buffer]
    } else {
        state.len += 9
        const view = new DataView(new ArrayBuffer(8))
        view.setBigUint64(0, BigInt(big), true)
        return [high | 15, view.buffer]
    }
}

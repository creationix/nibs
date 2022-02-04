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
 * @returns {{little:number,big:number,len:number}}
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
 * @returns {number|boolean|null|Uint8Array|string|NibsList|NibsMap}
 */
function decodeAny(data, offset) {
    const { little, big, len } = decodePair(data, offset)
    switch (little) {
        case 0: // Integer
            return big
        case 1: // NegInteger
            return -big
        case 2: // FloatingPoint
            return decodeFloat(big)
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
            return new Uint8Array(data.buffer, data.byteOffset + offset + len, big)
        case 5: // String
            return new TextDecoder().decode(new Uint8Array(data.buffer, data.byteOffset + offset + len, big))
        case 6: // List
            return lazyList(data.buffer, data.byteOffset + offset + len, big)
        case 7: // Map
            return lazyMap(data.buffer, data.byteOffset + offset + len, big)
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
    const len = sizeAny(val)
    const data = new DataView(new ArrayBuffer(len))
    const offset = encodeAny(data, 0, val)
    if (offset !== len) {
        console.log({ data, offset, len })
        throw new Error("length mismatch when encoding")
    }
    return new Uint8Array(data.buffer, data.byteOffset, data.byteLength)
}

const converter = new DataView(new ArrayBuffer(8))

/**
 * @param {number} val
 * @returns {BigInt}
 */
function encodeFloat(val) {
    converter.setFloat64(0, val, true)
    return converter.getBigUint64(0, true)
}

/**
 * @param {BigInt} val
 * @returns {number}
 */
function decodeFloat(val) {
    converter.setBigUint64(0, val, true)
    return converter.getFloat64(0, true)
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @param {number} val
 * @returns {number}
 */
function encodeAny(data, offset, val) {
    const type = typeof val
    switch (type) {
        case "number":
            if (isNaN(val))
                return encodePair(data, offset, 3, 3)
            if (val === Infinity)
                return encodePair(data, offset, 3, 4)
            if (val === -Infinity)
                return encodePair(data, offset, 3, 5)
            if (val === Math.floor(val)) {
                if (val >= 0) {
                    return encodePair(data, offset, 0, val)
                } else {
                    return encodePair(data, offset, 1, -val)
                }
            }
            return encodePair(data, offset, 2, encodeFloat(val))
        case "boolean":
            return encodePair(data, offset, 3, val ? 1 : 0)
        case "object":
            if (val === null)
                return encodePair(data, offset, 3, 2)
            if (ArrayBuffer.isView(val))
                return encodeBinary(data, offset, val)
            if (Array.isArray(val))
                return encodeArray(data, offset, val)
            return encodeObject(data, offset, val)
        case "string":
            return encodeString(data, offset, val)
    }
    throw new TypeError("Unsupported type " + type)
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @param {string} str
 * @returns {number}
 */
function encodeString(data, offset, str) {
    return encodeBinary(data, offset, new TextEncoder().encode(str), 5)
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @param {ArrayBufferView} buf
 * @param {number} small?
 * @returns {number}
 */
function encodeBinary(data, offset, buf, small = 4) {
    offset = encodePair(data, offset, small, buf.byteLength)
    const target = new Uint8Array(data.buffer, data.byteOffset, data.byteLength)
    const bytes = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength)
    target.set(bytes, offset)
    return offset + buf.byteLength
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @param {any[]} list
 * @returns {number}
 */
function encodeArray(data, offset, list) {
    let len = 0
    for (const item of list) {
        len += sizeAny(item)
    }
    offset = encodePair(data, offset, 6, len)
    for (const item of list) {
        offset = encodeAny(data, offset, item)
    }
    return offset
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @param {Record<string,any>} map
 * @returns {number}
 */
function encodeObject(data, offset, map) {
    let len = 0
    for (const key in map) {
        len += sizeAny(key)
        len += sizeAny(map[key])
    }
    offset = encodePair(data, offset, 7, len)
    for (const key in map) {
        offset = encodeAny(data, offset, key)
        offset = encodeAny(data, offset, map[key])
    }
    return offset
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @param {number} small u4 sized number to encode
 * @param {number} big up to u64 sized number to encode
 * @returns {number} new offset
 */
function encodePair(data, offset, small, big) {
    const high = small << 4
    if (big < 0xc) {
        data.setUint8(offset++, high | big)
    } else if (big < 0x100) {
        data.setUint8(offset++, high | 12)
        data.setUint8(offset++, big)
    } else if (big < 0x10000) {
        data.setUint8(offset++, high | 13)
        data.setUint16(offset, big, true)
        offset += 2
    } else if (big < 0x100000000) {
        data.setUint8(offset++, high | 14)
        data.setUint32(offset, big, true)
        offset += 4
    } else {
        data.setUint8(offset++, high | 15)
        data.setBigUint64(offset, BigInt(big), true)
        offset += 8
    }
    return offset
}

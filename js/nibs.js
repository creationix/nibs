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
            return { little, big: data.getUint16(offset), len: 3 }
        case 0xe:
            return { little, big: data.getUint32(offset), len: 5 }
        case 0xf:
            return { little, big: data.getBigUint64(offset), len: 9 }
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
        case 2: // Simple
            switch (big) {
                case 0: // false
                    return false
                case 1: // true
                    return true
                case 2: // null
                    return null
            }
            throw new Error("Unexpected nibs simple subtype: " + big)
        case 4: // Binary
            return new Uint8Array(data.buffer, data.byteOffset + offset + len, big)
        case 5: // String
            return new TextDecoder().decode(new Uint8Array(data.buffer, data.byteOffset + offset + len, big))
        case 6: // List
            return new NibsList(data.buffer, data.byteOffset + offset + len, big)
        case 7: // Map
            return new NibsMap(data.buffer, data.byteOffset + offset + len, big)
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

const nibsTag = Symbol("nibs")

class NibsList extends Array {

    /**
     * @param {ArrayBuffer} buffer
     * @param {number} byteOffset
     * @param {number} byteLength
     */
    constructor(buffer, byteOffset, byteLength) {
        super(0)
        this[nibsTag] = new DataView(buffer, byteOffset, byteLength)
        return new Proxy(this, NibsList.handler)
    }

    *[Symbol.iterator]() {
        const data = this[nibsTag]
        let offset = 0
        while (offset < data.byteLength) {
            yield decodeAny(data, offset)
            offset += size(data, offset)
        }
    }
    // get length() {
    //     const data = this[nibsTag]
    //     let count = 0
    //     let offset = 0
    //     while (offset < data.byteLength) {
    //         count++
    //         offset += size(data, offset)
    //     }
    //     return count
    // }
}


/**@type {ProxyHandler<NibsList>} */
NibsList.handler = {
    get(target, property, receiver) {
        console.log("GET", { property })
        if (typeof property === "string") {
            const index = +property
            if (index === index | 0) {
                const data = target[nibsTag]
                let offset = 0
                while (offset < data.byteLength) {
                    if (index <= 0) {
                        return decodeAny(data, offset)
                    }
                    offset += size(data, offset)
                    index--
                }
            }
        }
        return Reflect.get(target, property, receiver)
    }
};

///////////////////////////////////////////////////////////////////////////

class NibsMap {
    /**
     * @param {ArrayBuffer} buffer
     * @param {number} byteOffset
     * @param {number} byteLength
     */
    constructor(buffer, byteOffset, byteLength) {
        this[nibsTag] = new DataView(buffer, byteOffset, byteLength)
        return new Proxy(this, NibsMap.handler)
    }
}


/**@type {ProxyHandler<NibsMap>} */
NibsMap.handler = {
    get(target, property, receiver) {
        const data = target[nibsTag]
        let offset = 0
        while (offset < data.byteLength) {
            const key = decodeAny(data, offset)
            offset += size(data, offset)
            if (key == property) {
                return decodeAny(data, offset)
            }
            offset += size(data, offset)
        }
    },
    ownKeys(target) {
        const keys = [];
        const data = target[nibsTag]
        let offset = 0
        while (offset < data.byteLength) {
            keys.push(decodeAny(data, offset))
            offset += size(data, offset)
            offset += size(data, offset)
        }
        return keys
    },
    getOwnPropertyDescriptor(target, property) {
        return {
            enumerable: true,
            configurable: true,
        }
    }
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
    const type = Object.prototype.toString.call(val)
    switch (type) {
        case "[object Number]":
            if (val === Math.floor(val)) {
                return sizePair(Math.abs(val))
            }
            throw new Error("TODO: support floats")
        case "[object Boolean]":
        case "[object Null]":
            return 1
        case "[object String]": {
            // TODO: see if there is a faster way to get this length.
            const len = (new TextEncoder().encode(val)).byteLength
            return sizePair(len) + len
        }
        case "[object Uint8Array]": {
            return sizePair(val.byteLength) + val.byteLength
        }
        case "[object Array]":
            return sizeArray(val)
        case "[object Object]":
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

/**
 * @param {DataView} data
 * @param {number} offset
 * @param {number} val
 * @returns {number}
 */
function encodeAny(data, offset, val) {
    const type = Object.prototype.toString.call(val)
    switch (type) {
        case "[object Number]":
            if (val === Math.floor(val)) {
                if (val >= 0) {
                    return encodePair(data, offset, 0, val)
                } else {
                    return encodePair(data, offset, 1, -val)
                }
            }
            throw new Error("TODO: support floats")
        case "[object Boolean]":
            return encodePair(data, offset, 2, val ? 1 : 0)
        case "[object Null]":
            return encodePair(data, offset, 2, 2)
        case "[object Uint8Array]":
            return encodeUint8Array(data, offset, val)
        case "[object String]":
            return encodeString(data, offset, val)
        case "[object Array]":
            return encodeArray(data, offset, val)
        case "[object Object]":
            return encodeObject(data, offset, val)
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
    return encodeUint8Array(data, offset, new TextEncoder().encode(str), 6)
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @param {Uint8Array} buf
 * @param {number} small?
 * @returns {number}
 */
function encodeUint8Array(data, offset, buf, small = 5) {
    offset = encodePair(data, offset, small, buf.byteLength)
    const target = new Uint8Array(data.buffer, data.byteOffset, data.byteLength)
    target.set(buf, offset)
    return offset + buf.byteLength
}

/**
 * @param {DataView} data
 * @param {number} offset
 * @param {any[]} list
 * @returns {number}
 */
function encodeArray(data, offset, list) {
    offset = encodePair(data, offset, 6, sizeArray(list))
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
    offset = encodePair(data, offset, 7, sizeObject(map))
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
        data.setUint16(offset, big)
        offset += 2
    } else if (big < 0x100000000) {
        data.setUint8(offset++, high | 14)
        data.setUint32(offset, big)
        offset += 4
    } else {
        data.setUint8(offset++, high | 15)
        data.setBigUint64(offset, big)
        offset += 8
    }
    return offset
}

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

// local function encode_pair(small, big)
//     local pair = lshift(small, 4)
// if big < 0xc then
// return 1, bor(pair, big)
//     elseif big < 0x100 then
// return 2, { bor(pair, 12), big }
//     elseif big < 0x10000 then
// return 3, { bor(pair, 13), U16Box { big }
// }
//     elseif big < 0x100000000 then
// return 5, { bor(pair, 14), U32Box { big } }
//     else
// return 9, { bor(pair, 15), U64Box { big } }
// end
// end

// ---@type table
// ---@return boolean
// local function is_list(val)
//     local i = 1
// for key in pairs(val) do
//     if key ~= i then return false end
// i = i + 1
// end
// return true
// end

// local encode_any

// local function encode_list(list)
//     local total = 0
//     local body = {}
// for i = 1, #list do
//         local size, entry = encode_any(list[i])
//         insert(body, entry)
// total = total + size
// end
//     local size, head = encode_pair(6, total)
// return size + total, { head, body }
// end

// local function encode_map(map)
//     local total = 0
//     local body = {}
// for k, v in pairs(map) do
//         local size, entry = encode_any(k)
//         insert(body, entry)
// total = total + size
// size, entry = encode_any(v)
// insert(body, entry)
// total = total + size
// end
//     local size, head = encode_pair(7, total)
// return size + total, { head, body }
// end


// ---@param val any
// function encode_any(val)
//     local kind = type(val)
// if kind == "number" then
// if val >= 0 then
// return encode_pair(0, val)-- Integer
//         else
// return encode_pair(1, -val)-- Negative Integer
// end
//     elseif kind == "boolean" then
// return encode_pair(2, val and 1 or 0)-- Simple true / false
//     elseif kind == "nil" then
// return encode_pair(2, 2)-- Simple nil
//     elseif kind == "cdata" then
//         local len = sizeof(val)
//         local size, head = encode_pair(4, len)
// return size + len, { head, val }
//     elseif kind == "string" then
//         local len = #val
//         local size, head = encode_pair(5, len)
// return size + len, { head, val }
//     elseif kind == "table" then
// if is_list(val) then
// return encode_list(val)
//         else
// return encode_map(val)
// end
//     else
// error("Unsupported value type: "..kind)
// end
// end

// local function encode(val)
//     local i = 0
//     local size, data = encode_any(val)
//     local buf = Slice(size)
//     local function write(d)
//         local kind = type(d)
// if kind == "number" then
// buf[i] = d
// i = i + 1
//         elseif kind == "cdata" then
//             local len = sizeof(d)
// copy(buf + i, d, len)
// i = i + len
//         elseif kind == "string" then
// copy(buf + i, d)
// i = i + #d
//         elseif kind == "table" then
// for j = 1, #d do
//     write(d[j])
//             end
//         end
// end
// write(data)
// assert(size == i)
// return buf
// end

// metatype(StructNibsList, NibsList)
// metatype(StructNibsMap, NibsMap)

// --- Returns true if a value is a virtual nibs container.
// local function is(val)
// return istype(StructNibsList, val)
//         or istype(StructNibsMap, val)
// end

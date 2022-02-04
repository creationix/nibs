import { decode, encode } from "./nibs.js"

/** @type [any,string][] */
const tests = [
    // Integer
    [1, "\x01"],
    [42, "\x0c\x2a"],
    [500, "\x0d\xf4\x01"],
    [0xdeadbeef, "\x0e\xef\xbe\xad\xde"],
    [0x123456789abcdef0n, "\x0f\xf0\xde\xbc\x9a\x78\x56\x34\x12"],
    // NegInt
    [-1, "\x11"],
    [-42, "\x1c\x2a"],
    [-500, "\x1d\xf4\x01"],
    [-0xdeadbeef, "\x1e\xef\xbe\xad\xde"],
    [-0x123456789abcdef0n, "\x1f\xf0\xde\xbc\x9a\x78\x56\x34\x12"],
    // Float
    [Math.PI, "\x2f\x18\x2d\x44\x54\xfb\x21\x09\x40"],
    // Simple
    [false, "\x30"],
    [true, "\x31"],
    [null, "\x32"],
    [NaN, "\x33"],
    [Infinity, "\x34"],
    [-Infinity, "\x35"],
    // Binary
    // null terminated C string
    [new TextEncoder().encode("Binary!\0"), "\x48Binary!\0"],
    // C byte array
    [new Uint8Array([1, 2, 3]), "\x43\x01\x02\x03"],
    // C double array
    [new Float64Array([Math.PI]), "\x48\x18\x2d\x44\x54\xfb\x21\x09\x40"],
    // String
    ["Hello", "\x55Hello"],
    // list
    [[1, 2, 3], "\x63\x01\x02\x03"],
    // map
    [{ name: "Tim" }, "\x79\x54name\x53Tim"],
]

/**
 * @param {Uint8Array} a
 * @param {Uint8Array} b
 */
function equalBinary(a, b) {
    if (a === b) return true
    if (a.byteLength !== b.byteLength) return false
    console.log({ a, b })
    for (let i = 0, l = a.byteLength; i < l; i++) {
        if (a[i] !== b[i]) return false
    }
    return true
}

/**
 * @param {any[]} a
 * @param {any[]} b
 */
function equalArray(a, b) {
    if (a.length !== b.length) return false
    for (let i = 0; i < a.length; i++) {
        if (!equal(a[i], b[i])) return false
    }
    return true
}

/**
 * @param {object} a
 * @param {object} b
 */
function equalObject(a, b) {
    if (a == b) return true
    if (!a || !b) return false
    for (const key in a) {
        if (!equal(a[key], b[key])) return false
    }
    for (const key in b) {
        if (!equal(a[key], b[key])) return false
    }
    return true
}

/**
 * @param {any} a
 * @param {any} b
 * @returns {boolean}
 */
function equal(a, b) {
    if (a === b) return true
    if (isNaN(a) && isNaN(b)) return true
    if (ArrayBuffer.isView(a) && ArrayBuffer.isView(b)) {
        return equalBinary(
            new Uint8Array(a.buffer, a.byteOffset, a.byteLength),
            new Uint8Array(b.buffer, b.byteOffset, b.byteLength))
    }
    if (Array.isArray(a) && Array.isArray(b)) {
        return equalArray(a, b)
    }
    const type = typeof a
    if (type != typeof b) return false
    switch (type) {
        case "number":
        case "string":
        case "boolean":
            return false
        case "object":
            return equalObject(a, b)
    }
    console.log({ a, b, type })
    throw new Error("TODO")

}

/**
 * @param {string} str
 * @returns {Uint8Array}
 */
const tobin = str => new Uint8Array(str.split("").map(c => c.charCodeAt(0)))

for (const [val, exp] of tests) {
    console.log("\n\n")
    console.log("val", val)
    const expected = tobin(exp)
    console.log("expected", expected)
    const encoded = encode(val)
    console.log("encoded ", encoded)
    if (!equalBinary(encoded, expected)) {
        console.log(Buffer.from(encoded))
        throw new Error("Encoding mismatch")
    }
    const decoded = decode(encoded)
    console.log("decoded ", decoded)
    if (!equal(decoded, val)) {
        throw new Error("Decoding mismatch")
    }

    // JSON can't encode binary of bigint, so skip json tests for those
    if (ArrayBuffer.isView(val) || typeof val === "bigint") continue
    const json = JSON.stringify(val)
    console.log(json)
    const out = JSON.stringify(decoded)
    console.log(out)
    if (json !== out) {
        throw new Error("JSON mismatch in decoded")
    }
}

console.log("\n\n")
const val = decode(encode([1, 2, [3, 4], 5, 6]))
console.log(val)
console.log(val[2])
console.log(val)
console.log(val[2][0])
console.log(val)

console.log("\n\n")
const val2 = decode(encode({ name: "Tim", colors: ["red", "blue", "orange", "green"] }))
console.log(val2)
console.log(val2.name)
console.log(val2)
console.log(val2.colors)
console.log(val2)
console.log(val2.colors[1])
console.log(val2)

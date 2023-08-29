import { xxh64 } from "../xxhash64.js"

/** @type {[Uint8Array,number,number,bigint][]} */
const tests = [
    [utf8``, 0, 0x02cc5d05, 0xef46db3751d8e999n],
    [utf8``, 1, 0x0b2cb792, 0xd5afba1336a3be4bn],
    [utf8`a`, 0, 0x550d7456, 0xd24ec4f1a98c6e5bn],
    [utf8`as`, 0, 0x9d5a0464, 0x1c330fb2d66be179n],
    [utf8`asd`, 0, 0x3d83552b, 0x631c37ce72a97393n],
    [utf8`asdf`, 0, 0x5e702c32, 0x415872f599cea71en],
    [utf8`Call me Ishmael.`,
        0, 0x02f60492, 0x6d04390fc9d61a90n],
    [utf8`Some years ago--never mind how long precisely-`,
        0, 0x5f85f0d4, 0x8f26f2b986afdc52n],
    // Exactly 63 characters, which exercises all code paths.
    [utf8`Call me Ishmael. Some years ago--never mind how long precisely-`,
        0, 0x6f320359, 0x02a2e85470d6fd96n],
    [utf8`0123456789abcdef`,
        0, 0xc2c45b69, 0x5c5b90c34e376d0bn],
    [utf8`0123456789abcdef0123456789abcdef`,
        0, 0xeb888d30, 0x642a94958e71e6c5n],
]

for (const [input, seed, h32, h64] of tests) {
    let hash = xxh64(input, BigInt(seed))
    console.log("\nINPUT " + JSON.stringify(Buffer.from(input).toString()))
    console.log("EXPECTED xxh32 " + h32.toString(16))
    console.log("ACTUAL   xxh32 ")
    console.log("EXPECTED xxh64 " + h64.toString(16))
    console.log("ACTUAL   xxh64 " + hash.toString(16))
    if (hash != h64) {
        throw new Error("HASH64 MISMATCH")
    }
}

/**
 * @param {TemplateStringsArray} arr 
 * @returns Buffer
 */
function hex(arr) {
    return Buffer.from(arr[0], "hex")
}

/**
 * @param {TemplateStringsArray} arr 
 * @returns Uint8Array
 */
function utf8(arr) {
    return new TextEncoder().encode(arr[0])
}

import { xxh64 } from "./xxhash64.js"

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
    // // Exactly 63 characters, which exercises all code paths.
    // [utf8`Call me Ishmael.Some years ago--never mind how long precisely - `,
    //     0, 0x6f320359, 0x02a2e85470d6fd96n],
    // [utf8`0123456789abcdef`,
    //     0, 0xc2c45b69, 0x5c5b90c34e376d0bn],
    // [utf8`0123456789abcdef0123456789abcdef`,
    //     0, 0xeb888d30, 0x642a94958e71e6c5n],

    // // Common nibs values

    // //Int(0 - 6)
    // [hex`00`, 0, 0xcf65b03e, 0xe934a84adb052768n],
    // [hex`02`, 0, 0xd5403278, 0x4b79b8c95732b0e7n],
    // [hex`04`, 0, 0xebc0cebc, 0x64b9da3ed69d6732n],
    // [hex`06`, 0, 0xc9b8f720, 0x5896bb9a27ab7ba5n],
    // [hex`08`, 0, 0x452b0672, 0x431f0f810a7002a7n],
    // [hex`0a`, 0, 0x81c9d352, 0xcafc7706cee4572bn],
    // [hex`0c0c`, 0, 0x77cab09a, 0x90f2cfe93880eb7bn],
    // // false/true/null
    // [hex`20`, 0, 0x072e1494, 0x079cf5ceb668638dn],
    // [hex`21`, 0, 0x9c4e9f74, 0x9ea4029ff0912cb8n],
    // [hex`22`, 0, 0x99ae6e62, 0x89f45523b5b446aen],
    // // pi/inf/-inf/nan
    // [hex`1f182d4454fb210940`, 0, 0x36a39797, 0x954ccee0fb5ee767n],
    // [hex`1f000000000000f07f`, 0, 0x64f4be21, 0x04e80133d19091d6n],
    // [hex`1f000000000000f0ff`, 0, 0x06e6a447, 0xf6b64012a65883f6n],
    // [hex`1f000000000000f8ff`, 0, 0xf755ac37, 0x7406dc284ae4491cn],
    // // "name" / "Nibs"
    // [hex`946e616d65`, 0, 0xdce801fa, 0xff0dd0ea8d956135n],
    // [hex`944e696273`, 0, 0x5c2d9a82, 0x9d97f2fd3ab72bean],

]

for (const [input, seed, h32, h64] of tests) {
    console.log({ input, seed, h32, h64 })
    let hash = xxh64(input, BigInt(seed))
    if (hash != h64) {
        console.log({ hash })
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

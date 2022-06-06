// xxHash
// https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md#xxh64-algorithm-description

const PRIME64_1 = 0x9E3779B185EBCA87n
const PRIME64_2 = 0xC2B2AE3D27D4EB4Fn
const PRIME64_3 = 0x165667B19E3779F9n
const PRIME64_4 = 0x85EBCA77C2B2AE63n
const PRIME64_5 = 0x27D4EB2F165667C5n
const MASK = 0xffffffffffffffffn

/**
 * xxhash64
 * @param {ArrayBufferView} data 
 * @param {bigint} seed 
 * @returns {bigint}
 */
export function xxh64(data, seed) {
    let ptr = 0
    const len = data.byteLength
    const u64 = new BigUint64Array(data.buffer, data.byteOffset, data.byteLength)
    const u32 = new Uint32Array(data.buffer, data.byteOffset, data.byteLength)
    const u8 = new Uint8Array(data.buffer, data.byteOffset, data.byteLength)

    let h64 = 0n
    if (len >= 32) {

        let acc1 = (seed + PRIME64_1 + PRIME64_2) & MASK
        let acc2 = (seed + PRIME64_2) & MASK
        let acc3 = (seed) & MASK
        let acc4 = (seed - PRIME64_1) & MASK

        // For every chunk of 4 words, so 4 * 64bits = 32 bytes
        for (let i = ptr >> 3, l = len - 32; ptr <= l; ptr += 32) {
            acc1 = round64(acc1, u64[i++])
            acc2 = round64(acc2, u64[i++])
            acc3 = round64(acc3, u64[i++])
            acc4 = round64(acc4, u64[i++])
        }

        // Convergence
        h64 = (rotl64(acc1, 1n) + rotl64(acc2, 7n)
            + rotl64(acc3, 12n) + rotl64(acc4, 18n)) & MASK

        h64 = merge_round64(h64, acc1)
        h64 = merge_round64(h64, acc2)
        h64 = merge_round64(h64, acc3)
        h64 = merge_round64(h64, acc4)

    } else {
        // when input is smaller than 32 bytes
        h64 = (seed + PRIME64_5) & MASK
    }

    h64 = h64 + BigInt(len)

    console.log("Before extra", ptr, h64)
    // For the remaining words not covered above, either 0, 1, 2 or 3
    for (let i = ptr >> 3, l = len - 8; ptr <= l; ptr += 8) {
        h64 = (rotl64(h64 ^ round64(0n, u64[i++]), 27n) * PRIME64_1 + PRIME64_4) & MASK
        console.log("extra-word", ptr, h64)
    }

    // For the remaining half word.That is when there are more than 32bits
    // remaining which didn't make a whole word.
    for (; ptr + 4 <= len; ptr += 4) {
        h64 = (rotl64(h64 ^ ((BigInt(u32[ptr >> 2]) * PRIME64_1) & MASK), 23n) * PRIME64_2 + PRIME64_3) & MASK
    }

    // For the remaining bytes that didn't make a half a word (32bits),
    // either 0, 1, 2 or 3 bytes, as 4bytes = 32bits = 1 / 2 word.
    for (; ptr + 1 <= len; ptr++) {
        h64 = (rotl64(h64 ^ ((BigInt(u8[ptr]) * PRIME64_5) & MASK), 11n) * PRIME64_1) & MASK
    }

    // Finalize
    h64 ^= h64 >> 33n
    h64 = (h64 * PRIME64_2) & MASK
    h64 ^= h64 >> 29n
    h64 = (h64 * PRIME64_3) & MASK
    h64 ^= h64 >> 32n
    return h64

}

/**
 * @param {bigint} acc 
 * @param {bigint} value 
 * @returns {bigint}
 */
function round64(acc, value) {
    acc = (acc + value * PRIME64_2) & MASK
    acc = rotl64(acc, 31n)
    acc = imul64(acc, PRIME64_1)
    return acc
}

function merge_round64(acc, val) {
    val = round64(0n, val)
    acc ^= val
    acc += PRIME64_1 + PRIME64_4
    return acc
}

/**
 * Rotate left modulo 64-bit
 * @param {bigint} num 
 * @param {bigint} bits 
 * @returns {bigint}
 */
function rotl64(num, bits) {
    bits = BigInt(bits)
    return (num << bits | num >> (64n - bits)) & MASK
}

/**
 * Modular integer multiplication
 * @param {bigint} a 
 * @param {bigint} b 
 * @returns {bigint}
 */
function imul64(a, b) {
    return (a * b) & MASK
}

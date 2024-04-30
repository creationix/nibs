// import * as XXHash from "@node-rs/xxhash"
// export const xxh64 = XXHash.xxh64

// The JS IMPLEMENTATION works, but is much slower.

// xxHash
// https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md#xxh64-algorithm-description

const PRIME64_1 = 0x9E3779B185EBCA87n
const PRIME64_2 = 0xC2B2AE3D27D4EB4Fn
const PRIME64_3 = 0x165667B19E3779F9n
const PRIME64_4 = 0x85EBCA77C2B2AE63n
const PRIME64_5 = 0x27D4EB2F165667C5n
const MODULUS = 0x10000000000000000n

/**
 * xxhash64
 * @param {ArrayBufferView} data
 * @param {bigint} seed
 * @returns {bigint}
 */
export function xxh64(data, seed) {
    let ptr = 0
    const len = data.byteLength
    const last = ptr + len
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength)

    let h64 = 0n
    if (len >= 32) {

        let acc1 = iadd64(seed, PRIME64_1, PRIME64_2)
        let acc2 = iadd64(seed, PRIME64_2)
        let acc3 = BigInt(seed % MODULUS)
        let acc4 = isub64(seed, PRIME64_1)

        // For every chunk of 4 words, so 4 * 64bits = 32 bytes
        const limit = last - 32
        do {
            acc1 = round64(acc1, view.getBigUint64(ptr, true))
            acc2 = round64(acc2, view.getBigUint64(ptr + 8, true))
            acc3 = round64(acc3, view.getBigUint64(ptr + 16, true))
            acc4 = round64(acc4, view.getBigUint64(ptr + 24, true))
            ptr += 32
        } while (ptr < limit)

        // Convergence
        h64 = iadd64(rotl64(acc1, 1n), rotl64(acc2, 7n), rotl64(acc3, 12n), rotl64(acc4, 18n))

        h64 = merge_round64(h64, acc1)
        h64 = merge_round64(h64, acc2)
        h64 = merge_round64(h64, acc3)
        h64 = merge_round64(h64, acc4)

    } else {
        // when input is smaller than 32 bytes
        h64 = iadd64(seed, PRIME64_5)
    }

    h64 = iadd64(h64, len)

    // For the remaining words not covered above, either 0, 1, 2 or 3
    while (ptr <= last - 8) {
        h64 = iadd64(imul64(rotl64(h64 ^ round64(0n, view.getBigUint64(ptr, true)), 27n), PRIME64_1), PRIME64_4)
        ptr += 8
    }

    // For the remaining half word.That is when there are more than 32bits
    // remaining which didn't make a whole word.
    while (ptr <= last - 4) {
        h64 = iadd64(imul64(rotl64(h64 ^ imul64(view.getUint32(ptr, true), PRIME64_1), 23n), PRIME64_2), PRIME64_3)
        ptr += 4
    }

    // For the remaining bytes that didn't make a half a word (32bits),
    // either 0, 1, 2 or 3 bytes, as 4bytes = 32bits = 1 / 2 word.
    while (ptr <= last - 1) {
        h64 = imul64(rotl64(h64 ^ imul64(view.getUint8(ptr), PRIME64_5), 11n), PRIME64_1)
        ptr += 1
    }

    // Finalize
    h64 ^= h64 >> 33n
    h64 = imul64(h64, PRIME64_2)
    h64 ^= h64 >> 29n
    h64 = imul64(h64, PRIME64_3)
    h64 ^= h64 >> 32n
    return h64

}

/**
 * @param {bigint} acc
 * @param {bigint} value
 * @returns {bigint}
 */
function round64(acc, value) {
    acc = iadd64(acc, imul64(value, PRIME64_2))
    acc = rotl64(acc, 31n)
    acc = imul64(acc, PRIME64_1)
    return acc
}

function merge_round64(acc, val) {
    val = round64(0n, val)
    acc ^= val
    acc = iadd64(imul64(acc, PRIME64_1), PRIME64_4)
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
    return (num << bits | num >> (64n - bits)) % MODULUS
}

/**
 * @param {number|bigint} a
 * @param {number|bigint} b
 * @returns {bigint}
 */
function imul64(a, b) {
    return BigInt(a) * BigInt(b) % MODULUS
}

/**
 * @param {number|bigint} a
 * @param {(number|bigint)[]} more
 * @returns {bigint}
 */
function iadd64(a, ...more) {
    a = BigInt(a)
    for (const num of more) {
        a += BigInt(num)
    }
    return a % MODULUS
}

/**
 * @param {number|bigint} a
 * @param {(number|bigint)} b
 * @returns {bigint}
 */
function isub64(a, b) {
    return (BigInt(a) - BigInt(b) + MODULUS * 2n) % MODULUS
}
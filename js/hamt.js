/**
 * @param {Iterable<[number,number]>} entries 
 * @param {number} bits per level
 * @returns {Uint8Array|Uint16Array|Uint32Array|BigUint64Array}
 */
function encode(entries, bits = 3) {
    if (bits < 3 || bits > 6 || bits % 1) throw new Error(`Invalid bitsize ${bits}`)

    const mask = (1 << bits) - 1
    let items = []
    const maxOffset = (1 << ((1 << bits) - 1)) - 1
    console.log({ bits, maxOffset })
    // Build the trie
    const root = {}
    for (const [hash, offset] of entries) {
        // If we ever discover that the current pointer size isn't big enough, 
        // start over at the next power of 2
        if (offset > maxOffset) return encode(entries, bits + 1)
        let level = 0
        let node = root
        while (true) {
            // If the node contains a leaf, split it and try again.
            if (node.hash) {
                const oldHash = node.hash
                const oldOffset = node.offset
                delete node.hash
                delete node.offset
                const subprefix =
                    node[(oldHash >> (bits * level)) & mask] = { hash: oldHash, offset: oldOffset }
                continue
            }

            let prefix = (hash >> (bits * level)) & mask
            // If the prefix already exists, follow it.
            if (node[prefix]) {
                node = node[prefix]
                level++
                continue
            }

            // Otherwise, insert it here.
            node[prefix] = { hash, offset }
            break
        }
    }
    console.log(root)
    if (bits === 3) return new Uint8Array(items)
    if (bits === 4) return new Uint16Array(items)
    if (bits === 5) return new Uint32Array(items)
    if (bits === 6) return new BigUint64Array(items)
    throw new Error("Unsupported segment bitsize")
}


const a = encode([
    [0b111111, 1000],
    [0b010101, 2000],
    [0b101111, 3000],
])


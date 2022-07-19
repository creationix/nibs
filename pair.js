function pair(x, y) {
    return x < y ? x + y * y : x * x + x + y
}

function zigzag(i) {
    return i < 0 ? i * -2 - 1 : i * 2
}

function encode(e, m) {
    return pair(zigzag(e), zigzag(m))
}

// function encode(f) {
//     const e = Math.floor(Math.log10(Math.abs(f)))
//     const m = Math.round(f / Math.pow(10, e))
//     return pair(zigzag(e), zigzag(m))
// }
const encoded = encode(3141592653589793, 15)
console.log({ encoded, log2: Math.log2(encoded) })

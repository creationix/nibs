import { decode, encode } from "./nibs.js"

const list = decode(
    "\x63\x01\x02\x03" // [1,2,3]
)
console.log("list")
console.log(list)

console.log("for..of")
for (const item of list) {
    console.log(item)
}

console.log("for(;;)")
for (let i = 0, l = list.length; i < l; i++) {
    console.log(i, list[i])
}

console.log("forEach")
list.forEach((list, i) => {
    console.log(i, list)
})

console.log("Array.from", Array.from(list))

console.log()
const map = decode(
    "\x79\x54name\x53Tim" // {name:"Tim"}
)

console.log("map", map)

console.log("Object.keys", Object.keys(map))

console.log("for..in")
for (const key in map) {
    console.log(key, map[key])
}

console.log("Object.values")
console.log(Object.values(map))

console.log("Object.entries")
console.log(Object.entries(map))

console.log("JSON.stringify", JSON.stringify(map))

console.log(encode(10))
console.log(encode(-10))
console.log(encode(42))
console.log(encode(-42))
console.log(encode(false))
console.log(encode(true))
console.log(encode(null))
console.log(encode("XXXX"))
console.log(encode("AAAABBBBCCCCDDDD"))
console.log(encode(new TextEncoder().encode("AAAABBBBCCCCDDDD")))
console.log(encode([20, 30, 10]))
console.log(encode({ a: 1, b: 2, c: 3 }))

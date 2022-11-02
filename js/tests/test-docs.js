import * as Nibs from '../index.js'
console.log(Nibs)

import { encode, decode } from '../index.js'
console.log({ encode, decode })

const encoded = Nibs.encode({ hello: "world" })
console.log({ encoded })
console.assert(ArrayBuffer.isView(encoded), "encode created typed array")
console.assert(encoded.length === 14, "sample should be 14 bytes")

const decoded = Nibs.decode(encoded)
console.log({ decoded })
console.assert(decoded.get('hello') === 'world', "decoded value has expected behavior")

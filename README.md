# Nibs Serialization Format

Nibs is a new binary serialization format with the following set of priorities:

[![Run JS Tests](https://github.com/creationix/nibs/actions/workflows/test-js.yaml/badge.svg)](https://github.com/creationix/nibs/actions/workflows/test-js.yaml)

[![Run Lua Tests](https://github.com/creationix/nibs/actions/workflows/test-lua.yaml/badge.svg)](https://github.com/creationix/nibs/actions/workflows/test-lua.yaml)

[![Run Lua Reverse Tests](https://github.com/creationix/nibs/actions/workflows/test-lua-reverse.yaml/badge.svg)](https://github.com/creationix/nibs/actions/workflows/test-lua-reverse.yaml)

## Fast Random Access Reads

This format is designed to be read in-place (similar to cap'n proto) so that arbitrarily large documents can be read with minimal memory or compute requirements.  For example a 1 TiB mega nibs document could be read from a virtual block device where blocks are fetched from the network on-demand and the initial latency to start walking the data structure would be nearly instant.  Large documents could also be written to local NVMe drives and loaded to RAM using memmap.

To enable this random access, all values are either inline (just the nibs pair) or contain a postfix length so that a single indirection can jump to the next value.  Also some types like the `Array` type enable O(1) lookup of arrays of any size with an inline index of fixed-width pointers that is read instead of scanning to the Nth entry.

## Self Documenting

Nibs documents are similar to JSON in that the objects are self documenting (unlike protobuf that depends on implicit external schemas).  This works very well for dynamic programming environments like JavaScript and Lua or for replacing existing JSON workloads.

But if a developer chooses to also have schemas, it's possible to encode values as a nibs `list` and then the code would know what each positional value it.

## Simple to Implement

One of the main goals of nibs vs existing formats is it aims to be simple implement.  It should be possible for a single developer with experience writing serilization libraries to have an initial working version very quickly so that new languages/tools can easily adopt it.  This also means that these libraries are likely to have no dependencies themselves keeping it lean.

This is a much simpler format than pretty much any of the existing formats except for maybe JSON.

## Simple to Understand

Another goal is for the format itself to be simple to understand and think about.  The nibs-pair encoding is the same for all value types.  The types are grouped into similar behavior.  Anything complex is pushed out to userspace.

## Superset of JSON

Any value that can be encoded in JSON can also be encoded in nibs.  In this way it's similar to msgpack and cbor format, but it's much faster to read since it doesn't require parsing the whole document first.

There is also a defined textual representation known as Tibs that is a superset of JSON.  This makes it even easier to integrate into systems that use JSON or need textual representations of data (like config files or documentation).

## Compact on the Wire

Nibs tries to balance between compactness and simplicity and finds a nice middle ground.  Binary data can be stored as-is (without base64) and small values are genereally smaller than JSON. For example `-10000` is only 3 bytes in nibs (vs 6 in JSON) and `false` is 1 byte (vs 5 in JSON). `"hi"` is 3 bytes (vs 4 in JSON), `[0,-1,1]` is 4 bytes (vs 8 in JSON), etc...

The `HexString` value type allows storing strings that contain an even number of lowercase hexadecimal using half the bytes.  For example `"deadbeef"` would only take 5 bytes (*4 bytes for the body and 1 byte for the header*) vs 10 for JSON (*8 for the body and 2 for the quotes*).  You can store your git sha1 hashes in nibs as strings and only use 22 bytes instead of 42 bytes!

Repeated values can be stored just once and then referenced later on using the `Scope` and `Ref` types.  For example, it's very common for a large JSON document to have an array of objects where each object repeats the same keys for each entry.`[{"name": ...}, {"name": ...}, ...]` would be encoded as `("name", [{@0: ...}, {@0: ...}, ...])` where `&0` is a `Ref` that takes 1 byte and `(...)` is a `Scope` containing the ref targets and the child value that contains the refs inline.

## Implementations

- [JavaScript](js/README.md)
- [LuaJit](lua/README.md)

## Binary Nibs Format Specification

All multi-byte numbers in this spec are assumed to be little-endian.

In this document *"should"* means that an implementation is recommended to work this way.
However *"must"* means that it is not considered spec compliant without said behavior.

Nibs documents are read right-to-left similar to the zipfile format.  This direction was chosen to make it easier to write performant streaming encoders and doesn't really make it harder to decode the format.  One interesting byproduct of this is it's possible to concatenate a nibs document with a native system executible (since they always read left-to-right and ignore garbage at the end).  This makes it possible to quickly turn nibs documents into standalone programs without any special build tools.

## Integer Pair Encoding

The core serialization structure in Nibs is the nibble pair (hence the name).

There are 5 possible encoding patterns depending on the size of the second number:

```js
                                    xxxx yyyy
                           yyyyyyyy xxxx 1100
                  yyyyyyyy yyyyyyyy xxxx 1101
yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy xxxx 1110
yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy xxxx 1111
yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy
```

Here the `x`s are a `u4` and the `y`s are semantically a `u64` using zero extension on the smaller numbers.

Having this 4-bit alignment on the header byte makes is easy to manually read nibs value from a hex dump for quick debugging.


> [!NOTE]
> Encoders *should* only use the smallest possible encoding for a given value.

> [!WARNING]
> Decoders *must* accept all.

## Nibs Value Types

For each encoded integer pair, the small number is the type and the big number is it's parameter:

```c++
enum Type {

    // Inline types.
    ZigZag    = 0, // big = zigzag encoded i64
    Float     = 1, // big = binary encoding of float
    Simple    = 2, // big = subtype (false, true, null)
    Ref       = 3, // big = reference offset into nearest parent RefScope array

    // slots 4-7 reserved

    // Prefixed length types.
    Bytes     = 8, // big = len (raw octets)
    Utf8      = 9, // big = len (utf-8 encoded unicode string)
    HexString = a, // big = len (lowercase hex string stored as binary)
    List      = b, // big = len (list of nibs values)
    Map       = c, // big = len (list of alternating nibs keys and values)
    Array     = d, // big = len (array index then list)
                   // small2 = width, big2 = count

    // slot e reserved

    Scope     = f, // big = len (wrapped value, then array of refs)
                   // small2 = width, big2 = count
};
```

### ZigZag Integers

The `integer` type has `i64` range, but is encoded with zigzag encoding to take advantage of the smaller nibs representations for common values.

This maps negative values to positive values while going back and forth:

`(0 = 0, -1 = 1, 1 = 2, -2 = 3, 2 = 4, -3 = 5, 3 = 6 ...)`

```c
// Convert between signed value and `u64` bitfield representations.
uint64_t encodeZigZag(int64_t i) {
  return (i >> 63) ^ (i << 1);
}
int64_t decodeZigZag(uint64_t i) {
  return (i >> 1) ^ -(i & 1);
}
```

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`0` | `<30>` | `<00>`
`-1` | `<2d31>` | `<01>`
`1` | `<31>` | `<02>`
`-2` | `<2d32>` | `<03>`
`2` | `<32>` | `<04>`
`42` | `<3432>` | `<54 0c>`
`1000` | `<31303030>` | `<d007 0d>`

### Floating Point Numbers

The `float` type is stored as binary-64 (aka `double`) bitcast to u64.

```c
// Convert between `f64` (double precision floating point) and `u64` bitfield representations.
uint64_t encodeDouble(double i) {
  return *(uint64_t*)(&i);
}
double decodeDouble(uint64_t i) {
  return *(double*)(&i);
}
```

This means that in practice it will nearly always use the largest representation since `double` almost always uses the high bits.

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`3.1415926535897930` | `332e313431353932363533353839373933` | `182d4454fb210940 1f`
`inf` | | `000000000000f07f 1f`
`-inf` | | `000000000000f0ff 1f`
`nan` | | `000000000000f8ff 1f`

### Simple SubTypes

The simple type has it's own subtype enum for booleans and null.

```c++
enum SubType {
    False     = 0,
    True      = 1,
    Null      = 2,

    // slots 3-7 reserved
};
```

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`false` | `<66616c7365>` | `<20>`
`true` | `<74727565>` | `<21>`
`null` | `<6e756c6c>` | `<22>`

### Bytes

Bytes are a container for raw octets.

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`<>` | | `<80>`
`<deadbeef>` | | `<deadbeef 84>`
`<0123456789abcdef>` | | `<0123456789abcdef 88>`
`<00112233445566778899aabbccddeeff>` | | `<00112233445566778899aabbccddeeff 10 8c>`


### Utf8 Unicode Strings

Most strings are stored as utf-8 encoded unicode wrapped in nibs.  Codepoints higher than 16-bits are allowed, but also are surrogate pairs.  It is recommended to not encode as surrogate pairs and use the native encoding utf-8 allows.

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`"🏵ROSETTE"` | `<22 f09f8fb5524f5345545445 22>` | `<f09f8fb5524f5345545445 9b>`
`"🟥🟧🟨🟩🟦🟪"` | `<22 f09f9fa5f09f9fa7f09f9fa8f09f9fa9f09f9fa6f09f9faa 22>` | `<f09f9fa5f09f9fa7f09f9fa8f09f9fa9f09f9fa6f09f9faa 18 9c>`
`"👶!"` | `<22 f09f91b621 22>` | `<f09f91b621 95>`

### Hex Strings

Hex Strings are an optimization for common string values that are an even number of lowercase hexadecimal characters.  They are stored in half the space by storing the pairs as bytes, but are strings externally.

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`"deadbeef"` | `<22 6465616462656566 22>` | `<deadbeef a4>`

### List

The `list` type is a ordered list of values.  It's encoded as zero or more nibs encoded values concatenated back to back.  These have O(n) lookup cost since the list of items needs to be scanned linearly.

```lua
b0 --> List(0)
--> []

b3 --> List(3)
  02 --> ZigZag(2)
  04 --> ZigZag(4)
  06 --> ZigZag(6)
--> [1,2,3]

b6 --> List(6)
  b1 --> List(1)
    02 --> ZigZag(2)
  b1 --> List(1)
    04 --> ZigZag(4)
  b1 --> List(1)
    06 --> ZigZag(6)
--> [[1],[2],[3]]
```

### Map

Map is the same, except the items are considered alternatinv keys and values.  Lookup by key is O(2n).

```lua
cb --> Map(11)
  94 --> Utf8(4)
    6e 61 6d 65 --> `n` `a` `m` `e`
  93 --> Utf8(3)
    54 69 6d --> `T` `i` `m`
  21 --> Simple(1)
  20 --> Simple(0)
--> {"name":"Tim",true:false}
```

### Array

The `array` type is like list, except it includes an array of pointers before the payload to enable O(1) lookups.

This index is encoded via a secondary nibs pair where small is the byte width of the pointers and big is the number of entries.  This is followed by the pointers as offset distances from the end of the index (the start of the list of values).

```lua
d7 --> Array(7)
  13 --> ArrayIndex(width=1,count=3)
    00 --> Pointer(0)
    01 --> Pointer(1)
    02 --> Pointer(2)
  02 --> ZigZag(2)
  04 --> ZigZag(4)
  06 --> ZigZag(6)
--> [1,2,3]
```

### Trie

A trie is an indexed map, this is done by creating a HAMT prefix trie from the nibs binary encoded map key hashed.

This index is a HAMT ([Hash Array Mapped Trie](https://en.wikipedia.org/wiki/Hash_array_mapped_trie)). The keys need to be mapped to uniformly distributed hashes.  By default nibs uses the [xxhash64](https://github.com/Cyan4973/xxHash) algorithm.

The secondary nibs pair is pointer width and size of trie in entries.

Example key hashing.

```c++
key = "name"                   // "name"
encoded = nibs.encode(key)     // <946e616d65>
seed = 0                       // 0
hash = xxhash64(encoded, seed) // 0xff0dd0ea8d956135ULL
```

```lua
ec 11 --> Trie-8(17)
  14 --> TrieIndex(width=4,count=4)
    00 --> HashSeed(0)
    21 --> Bitmask([0,5])
    8a --> Leaf(10)
    80 --> Leaf(0)
  94 --> Utf8(4)
    6e --> 'n'
    61 --> 'a'
    6d --> 'm'
    65 --> 'e'
  94 --> Utf8(4)
    4e --> 'N'
    69 --> 'i'
    62 --> 'b'
    73 --> 's'
  21 --> Simple(1)
  20 --> Simple(0)
--> {"name":"Nibs",true:false}
```

The same value with a worse seed chosen can show an internal node:

```lua
ec 13 --> Trie-8(19)
  16 --> IndexHeader(width=1,count=6)
    03 --> HashSeed(3)
    04 --> Bitmask([2])
    00 --> Pointer(0)
    22 --> Bitmask([1,5])
    80 --> Leaf(0)
    8a --> Leaf(10)
  94 --> Utf8(4)
    6e --> 'n'
    61 --> 'a'
    6d --> 'm'
    65 --> 'e'
  94 --> Utf8(4)
    4e --> 'N'
    69 --> 'i'
    62 --> 'b'
    73 --> 's'
  21 --> Simple(1)
  20 --> Simple(0)
--> {"name":"Nibs",true:false}
```

### HAMT Encoding

Each node in the trie index has a bitfield so that only used pointers need to be stored.

For example, consider a simplified 4-bit wide trie node with 4 hashes pointing to values at offsets 0,1,2,3:

- `0101` -> 0
- `0011` -> 1
- `1010` -> 2
- `1011` -> 3

Since the width is 4 bits, we can only consume the hash 2 bits at a time (starting with least-significant).

This means the root node has 3 entries for `01`, `10`, and `11`.  Since two keys share the `11` prefix a second node is needed.

```c++
// Hash config
 0000 // (seed 0)
// Root Node (xxxx)
 1110 // Bitfield [1,2,3]
1 000 // xx01 -> leaf 0
1 010 // xx10 -> leaf 2
0 000 // xx11 -> node 0
// Second Node (xx11)
 0101 // Bitfield [0,2]
1 001 // 0011 -> leaf 1
1 000 // 1011 -> leaf 3
```

For each 1 in the bitfield, a pointer follows in the node.  The least significant bit is 0, most significant is 3.

The pointers have a 1 prefix in the most significant position when pointing to a leaf node.  The value is offset from the start of the map (after the index).  Internal pointers start with a 0 in the most significant position followed by an offset from the end of the pointer.

### References

The `ref` type is used to reference into a userspace table of values.  The table is found by in the nearest `scope` wrapping the current value.

Typically this is the outermost value in a nibs document so that all data can reuse the same refs array.

This is encoded like array, except it's semantic meaning is special.  All entries except for the
last store the values of referenced values and the last entry can then reference them by index.

For example, consider the following value:

```js
// Original Value
[ { color: "red", fruits: ["apple", "strawberry"] },
  { color: "green", fruits: ["apple"] },
  { color: "yellow", fruits: ["apple", "banana"] } ]
```

A good refs table for this would be to pull out the repeated strings since their refs overhead is smaller then their encoding costs:

```js
// Refs Table
[ "color", "fruits", "apple" ]
```

Then the encoded value would look more like this with the refs applied.

```js
// encoding with refs and refsscope
RefScope(
  "color", "fruits", "apple",
  [ { &0: "red", &1: [&2, "strawberry"] },
    { &0: "green", &1: [&2] },
    { &0: "yellow", &1: [&2, "banana"] } ]
)
```

In this example, the refs table overhead is:

```txt
+2 <- RefScope-8
+1 <- IndexHeader
+3 <- 3 pointers 1 byte each
-5 <- "color" to Ref(0)
-6 <- "fruits" to Ref(1)
-5 <- "apple" to Ref(2)
-5 <- "color" to Ref(0)
-6 <- "fruits" to Ref(1)
-5 <- "color" to Ref(0)
-5 <- "apple" to Ref(2)
-6 <- "fruits" to Ref(1)
-5 <- "apple" to Ref(2)
+6 <- "color"
+7 <- "fruits"
+6 <- "apple"
-2 <- some nibs pairs jump to inline instead of 8 bit length
------------------------
25 bytes saved!
```

Another example is encoding `[4,2,3,1]` using the refs `[1,2,3,4]`

```lua
fc 0f --> Ref-8(15)
  14 --> ArrayIndex(width=1,count=4)
    00 --> Pointer(0) -> 1
    01 --> Pointer(1) -> 2
    02 --> Pointer(2) -> 3
    03 --> Pointer(3) -> 4
    04 --> Pointer(4) -> value
  02 --> ZigZag(2) = 1
  04 --> ZigZag(4) = 2
  06 --> ZigZag(6) = 3
  08 --> ZigZag(8) = 4
  b4 --> List(4)
    33 --> Ref(3) -> Pointer(8) -> 4
    31 --> Ref(1) -> Pointer(6) -> 2
    32 --> Ref(2) -> Pointer(7) -> 3
    30 --> Ref(0) -> Pointer(5) -> 1
--> RefScope(1,2,3,4,[&3,&1,&2,&0])
```

Note that refs are always zero indexed even if your language normally starts indices at 1.

```lua
fb --> Ref(11)
  13 --> ArrayIndex(width=1,count=2)
    00 --> Pointer(0) -> "dead"
    03 --> Pointer(6) -> "beef"
    06 --> Pointer(6) -> value
  a2 --> HexString(2)
    dead
  a2 --> HexString(2)
    beef
  31 --> Ref(1) -> "beef"
--> RefScope("dead","beef",&1)
```

The larger ref example from above would be encoded like this:

```lua
fc 4f --> Ref-8(79)
  14 --> ArrayIndex(width=1,count=3)
    00 --> Ptr(0)
    06 --> Ptr(6)
    0d --> Ptr(13)
    13 --> Ptr(19)
  95636f6c6f72 --> "color"
  96667275697473 --> "fruits"
  956170706c65 --> "apple"
  bc 35 --> List-8(53)
    cc 14 --> Map-8(20)
      30 --> Ref(0)
      93726564 --> "red"
      31 --> Ref(1)
      bc 0c --> List-8(12)
        32 --> Ref(2)
        9a73747261776265727279 --> "strawberry"
    ca --> Map(10)
      30 --> Ref(0)
      95677265656e --> "green"
      31 --> Ref(1)
      b1 --> List(1)
        32 --> Ref(2)
    cc 12 --> Map-8(18)
      30 --> Ref(0)
      9679656c6c6f77 --> "yellow"
      31 --> Ref(1)
      b8 --> List(8)
        32 --> Ref(2)
        9662616e616e61 --> "banana"
```

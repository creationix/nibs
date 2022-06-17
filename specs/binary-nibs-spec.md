# Binary Nibs Format Specification

All multi-byte numbers in this spec are assumed to be little-endian.

In this document *"should"* means that an implementation is recommended to work this way.
However *"must"* means that it is not considered spec compliant without said behavior.

## Integer Pair Encoding

There are 5 possible encoding patterns depending on the size of the second number:

```js
xxxx yyyy
xxxx 1100 yyyyyyyy
xxxx 1101 yyyyyyyy yyyyyyyy
xxxx 1110 yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy
xxxx 1111 yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy
```

Here the `x`s are a `u4` and the `y`s are semantically a `u64` using zero extension on the smaller numbers.

Encoders *should* only use the smallest possible encoding for a given value.

Decoders *must* accept all.

## Nibs Value Types

For each encoded integer pair, the first small number is the type and the big number is it's parameter:

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
    Unicode   = 9, // big = len (utf-8 encoded unicode string)
    HexString = a, // big = len (lowercase hex string stored as binary)
    List      = b, // big = len (list of nibs values)
    Map       = c, // big = len (list of alternating nibs keys and values)
    Array     = d, // big = len (array index then list)
                   // small2 = width, big2 = count 
    Trie      = e, // big = len (trie index then list)
                   // small2 = width, big2 = count
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

The best way to show this is with some examples going from encoded bytes to dissambly to final semantic meaning.

```lua
00 --> ZigZag(0)
--> 0

03 --> ZigZag(3)
--> -2

0c 54 --> ZigZag-8(84) 
--> 42

0d d0 07 --> ZigZag-16(2000)
--> 1000

0e 40 0d 03 00 --> ZigZag-32(200000)
--> 100000

0f 00 c8 17 a8 04 00 00 00 --> ZigZag-64(20000000000)
--> 10000000000
```

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

```lua
1f 18 2d 44 54 fb 21 09 40 --> Float-64(0x400921fb54442d18)
--> 3.1415926535897930

1f 00 00 00 00 00 00 f0 7f --> Float-64(0x7ff0000000000000)
--> inf

1f 00 00 00 00 00 00 f0 ff --> Float-64(0xfff0000000000000)
--> -inf

1f 00 00 00 00 00 00 f8 ff --> Float-64(0xfff8000000000000)
--> nan
```

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

These are simple indeed to encode.

```lua
20 --> Simple(1)
--> false

21 --> Simple(1)
--> true

22 --> Simple(2)
--> null
```

### Bytes

Bytes are a container for raw octets.

```lua
84 --> Bytes(4)
  de ad be ef --> 0xde 0xad 0xbe 0xef
--> <deadbeef>
```

### Unicode Strings

Most strings are stored as utf-8 encoded unicode wrapped in a unicode type in nibs.  Codepoints higher than 16-bits are allowed, but also are surrogate pairs.  It is recommended to not encode as surrogate pairs and use the smaller native encoding utf-8 allows.

```lua
9a --> Unicode(11)
  f0 9f 8f b5 --> `🏵`
  52 4f 53 45 54 54 45 --> `R` `O` `S` `E` `T` `T` `E`
--> "🏵ROSETTE"

9b 18 --> Unicode-8(24)
  f0 9f 9f a5 --> `🟥`
  f0 9f 9f a7 --> `🟧`
  f0 9f 9f a8 --> `🟨`
  f0 9f 9f a9 --> `🟩`
  f0 9f 9f a6 --> `🟦`
  f0 9f 9f aa --> `🟪`
--> "🟥🟧🟨🟩🟦🟪"

95 --> Unicode(4)
  f0 9f 91 b6 --> `👶`
  3f --> `?`
--> "👶?"
```

### Hex Strings

Hex Strings are an optimization for common string values that are an even number of lowercase hexadecimal characters.  They are stored in half the space by storing the pairs as bytes, but are strings externally.

```lua
a4 --> HexString(4)
  de ad be ef --> 0xde 0xad 0xbe 0xef
--> "deadbeef"
```

### List

### Map

### Array

### Trie

### References

The `ref` type is used to reference into a userspace table of values.  The table is found by in the nearest `scope` wrapping the current value.

Typically this is the outermost value in a nibs document so that all data can reuse the same refs dictionary.

This is encoded like array, except it's semantic meaning is special.
The first value is some container that has refs inside it
the rest of the values are the refs themselves offset by 1

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
  [ { &0: "red", &1: [&2, "strawberry"] },
    { &0: "green", &1: [&2] },
    { &0: "yellow", &1: [&2, "banana"] } ],
  "color", "fruits", "apple"
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
------------------------
23 saved bytes overall
```

Another example is encoding `[4,2,3,1]` using the refs `[1,2,3,4]`

```lua
ea 0e --> Ref-8(14)
  14 --> ArrayIndex(width=1,count=4)
    05 --> Pointer(5)
    06 --> Pointer(6)
    07 --> Pointer(7)
    08 --> Pointer(8)
  a3 --> List(3)
    33 --> Ref(3)
    31 --> Ref(1)
    32 --> Ref(2)
    30 --> Ref(0)
  02 --> ZigZag(2)
  04 --> ZigZag(4)
  06 --> ZigZag(6)
  08 --> ZigZag(8)
--> Scope([&3,&1,&2,&0],1,2,3,4)
```

Note that refs are always zero indexed even if your language normally starts indices at 1.  

###

Some more examples will explain this.

```lua
95 --> String(5)
  48 65 6c 6c 6f --> `H` `e` `l` `l` `o`
--> "Hello"

a4 --> HexString(4)
  de ad be ef --> 0xde 0xad 0xbe 0xef
--> "deadbeef"

a0 --> List(0)
--> []

a6 --> List(6)
  a1 --> List(1)
    02 --> ZigZag(2)
  a1 --> List(1)
    04 --> ZigZag(4)
  a1 --> List(1)
    06 --> ZigZag(6)
--> [[1],[2],[3]]

bb --> Map(11)
  94 --> String(4)
    6e 61 6d 65 --> `n` `a` `m` `e`
  93 --> String(3)
    54 69 6d --> `T` `i` `m`
  02 --> ZigZag(2)
  04 --> ZigZag(4)
--> {"name":"Tim",1:2}
```

The last 3 types are a bit more complex.  They are just like `List` and `Map` except they have an index before the list of values.

```lua
c7 --> Array(7) 
  13 --> ArrayIndex(width=1,count=3)
    00 --> Pointer(0)
    01 --> Pointer(1)
    02 --> Pointer(2)
  02 --> ZigZag(2)
  04 --> ZigZag(4)
  06 --> ZigZag(6)
--> [1,2,3]
```

### Floating Point Number

### Simple SubType

Currently only `true`, `false`, and `null` are specified and the rest of the range is reserved.

### String

The `string` type is assumed to be serialized as UTF-8 unicode.

Encoders should always emit normalized UTF-8 if possible.

Decoders are free to interpret bad encodings as makes sense for their application/language.

### Bytes

The `byte` type is a byte array for storing bulk binary octets.

### List

The `list` type is a ordered list of values.  It's encoded as zero or more nibs encoded values concatenated back to back.  These have O(n) lookup cost since the list of items needs to be scanned linearly.

For example `[1,2,3]` would be encoded as follows:

```c++
1010 0111 // List(3)
0000 0010 // Integer(1)
0000 0100 // Integer(2)
0000 0110 // Integer(3)
```

### Map

Map payloads are encoded as zero or more nibs encoded key and value pairs concatenated back to back.  These also have O(n) lookup costs.  It is recommended to use a userspace type via `tag` and probably `bytes` for more advanced data structures such as bloom filters or hash-array-mapped-tries.

For example, `{"name":"Nibs",true:false}` would be encoded as:

```c++
1011 1100 // Map-8bit
     0x0c // (len=12)
1001 0100 // String(len=4)
     0x6e // 'n'
     0x61 // 'a'
     0x6d // 'm'
     0x65 // 'e'
1001 0100 // String(len=4)
     0x4e // 'N'
     0x69 // 'i'
     0x62 // 'b'
     0x73 // 's'
0010 0001 // Simple(1)
0010 0000 // Simple(0)
```

### Array

The `array` type is like list, except it includes an array of pointers before the payload to enable O(1) lookups.

This index is encoded via a secondary nibs pair where small is the byte width of the pointers and big is the number of entries.  This is followed by the pointers as offset distances from the end of the index (the start of the list of values).

For example, the array `[1,2,3]` can be encoded as the following:

```c++
1100 0111 // Array(len=7)
0001 0011 // IndexHeader(width=1,count=3)
     0x00 // Offset(0)
     0x01 // Offset(1)
     0x02 // Offset(2)
0000 0010 // Integer(1)
0000 0100 // Integer(2)
0000 0110 // Integer(3)
```

### Trie

A trie is an indexed map, this is done by creating a HAMT prefix trie from the nibs binary encoded map key hashed.

The normal map encoding is at the end of the value just like with list/array.

For example, `{"name":"Nibs",true:false}` can be encoded as:

```js
{
     <5d765efe5d>: {...},
}
```

```c++
1101 1100 // Trie-8bit
     0x11 // (len=17)
0001 0100 // IndexHeader(width=1,count=4)
     0x00 // HashSeed(0)
 00100001 // Bitmask([0,5])
1 0001001 // 0 -> Leaf(10)
1 0000000 // 5 -> Leaf(0)
1001 0100 // String(len=4)
     0x6e // 'n'
     0x61 // 'a'
     0x6d // 'm'
     0x65 // 'e'
1001 0100 // String(len=4)
     0x4e // 'N'
     0x69 // 'i'
     0x62 // 'b'
     0x73 // 's'
0010 0001 // Simple(1)
0010 0000 // Simple(0)
```

The same value with a worse seed chosen can show an internal node:

```c++
1101 1100 // Trie=8bit
     0x13 // (len=19)
0001 0110 // IndexHeader(width=1,count=6)
     0x03 // HashSeed(3)
 00000100 // Bitmask([2])
0 0000000 // 2 -> Pointer(0)
 00100010 // Bitmask([1,5])
1 0000000 // 1 -> Leaf(0)
1 0001001 // 5 -> Leaf(10)
1001 0100 // String(len=4)
     0x6e // 'n'
     0x61 // 'a'
     0x6d // 'm'
     0x65 // 'e'
1001 0100 // String(len=4)
     0x4e // 'N'
     0x69 // 'i'
     0x62 // 'b'
     0x73 // 's'
0010 0001 // Simple(1)
0010 0000 // Simple(0)
```

This index is a HAMT ([Hash Array Mapped Trie](https://en.wikipedia.org/wiki/Hash_array_mapped_trie)). The keys need to be mapped to uniformly distributed hashes.  By default nibs uses the [xxhash64](https://github.com/Cyan4973/xxHash) algorithm.

The secondary nibs pair is pointer width and size of trie in entries.

Example key hashing.

```c++
key = "name"                   // "name"
encoded = nibs.encode(key)     // <946e616d65>
seed = 0                       // 0
hash = xxhash64(encoded, seed) // 0xff0dd0ea8d956135ULL
```

### HAMT Encoding

Each node in the tree has a bitfield so that only non-pointers need to be stored.

For example, consider a simplified 4-bit wide trie node with 4 keys point to values at offsets 0,1,2,3:

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

# Nibs Serialization Format

Nibs is a new binary serialization format with the following set of priorities:

[![Run JS Tests](https://github.com/creationix/nibs/actions/workflows/test-js.yaml/badge.svg)](https://github.com/creationix/nibs/actions/workflows/test-js.yaml)

[![Run Lua Tests](https://github.com/creationix/nibs/actions/workflows/test-lua.yaml/badge.svg)](https://github.com/creationix/nibs/actions/workflows/test-lua.yaml)

## Fast Random Access Reads

This format is designed to be read in-place (similar to cap'n proto) so that arbitrarily large documents can be read with minimal memory or compute requirements.  For example a 1 TiB mega nibs document could be read from a virtual block device where blocks are fetched from the network on-demand and the initial latency to start walking the data structure would be nearly instant.  Large documents could also be written to local NVMe drives and loaded to RAM using memmap.

To enable this random access, all values are either inline (just the nibs pair) or contain a prefix length so that a single indirection can jump to the next value.  Also some types like the `Array` type enable O(1) lookup of arrays of any size with an inline index of fixed-width pointers that is read instead of scanning to the Nth entry.

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

## Integer Pair Encoding

The core serialization structure in Nibs is the nibble pair (hence the name).

There are 5 possible encoding patterns depending on the size of the second number:

```js
xxxx yyyy
xxxx 1100 yyyyyyyy
xxxx 1101 yyyyyyyy yyyyyyyy
xxxx 1110 yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy
xxxx 1111 yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy
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

### `0` - ZigZag Integers

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
`42` | `<3432>` | `<0c 54>`
`1000` | `<31303030>` | `<0d d007>`

### `1` - Floating Point Numbers

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
`3.1415926535897930` | `332e313431353932363533353839373933` | `1f 182d4454fb210940`
`inf` | | `1f 000000000000f07f`
`-inf` | | `1f 000000000000f0ff`
`nan` | | `1f 000000000000f8ff`

### `2` - Simple SubTypes

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

### `8` - Bytes

Bytes are a container for raw octets.

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`<>` | | `<80>`
`<deadbeef>` | | `<84 deadbeef>`
`<0123456789abcdef>` | | `<88 0123456789abcdef>`
`<00112233445566778899aabbccddeeff>` | | `<8c10 00112233445566778899aabbccddeeff>`


### `9` - Utf8 Unicode Strings

Most strings are stored as utf-8 encoded unicode wrapped in nibs.  Codepoints higher than 16-bits are allowed, but also are surrogate pairs.  It is recommended to not encode as surrogate pairs and use the native encoding utf-8 allows.

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`"🏵ROSETTE"` | `<22 f09f8fb5 524f5345545445 22>` | `<9b f09f8fb5 524f5345545445>`
`"🟥🟧🟨🟩🟦🟪"` | `<22 f09f9fa5 f09f9fa7 f09f9fa8 f09f9fa9 f09f9fa6 f09f9faa 22>` | `<9c 18 f09f9fa5 f09f9fa7 f09f9fa8 f09f9fa9 f09f9fa6 f09f9faa>`
`"👶"` | `<22 f09f91b6 22>` | `<94 f09f91b6>`

### `a` - Hex Strings

Hex Strings are an optimization for common string values that are an even number of lowercase hexadecimal characters.  They are stored in half the space by storing the pairs as bytes, but are strings externally.

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`"deadbeef"` | `<22 6465616462656566 22>` | `<a4 deadbeef>`
`"0123456789abcdef"` | `<22 30313233343536373839616263646566 22>` | `<a8 0123456789abcdef>`

### `b` - List

The `list` type is a ordered list of values.  It's encoded as zero or more nibs encoded values concatenated back to back.  These have O(n) lookup cost since the list of items needs to be scanned linearly.

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`[]` | `<5b 5d>` | `<b0>`
`[1,2,3]` | `<5b 31 2c 32 2c 33 5d>` | `<b3 02 04 06>`
`[[1],[2],[3]]` | `<5b 5b 31 5d 2c 5b 32 5d 2c 5b 33 5d 5d>` | `<b6 b1 02 b1 04 b1 06>`

The last example in detail is:

```lua
b6 --> List(6)
  b1 --> List(1)
    02 --> ZigZag(2)
  b1 --> List(1)
    04 --> ZigZag(4)
  b1 --> List(1)
    06 --> ZigZag(6)
```

### `c` - Map

Map is the same as list, except the items are considered alternating keys and values.  Lookup by key is O(2n).

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`{"name":"Nibs"}` | `<7b 22 6e616d65 22 3a 22 4e696273 22 7d>` | `<ca 94 6e616d65 94 4e696273>`
`{"name":"Nibs",true:false}` | N/A | `<cc 0c 20 94 6e616d65 94 4e696273 21 20>`

```lua
cc 0c --> Map-8(12)
  94 --> Utf8(4)
    6e616d --> `n`,`a`,`m`,`e`
  94 --> Utf8(4)
    4e696273 --> `N`,`i`,`b`,`s`
  21 --> Simple(1)
  20 --> Simple(0)
```

> [!NOTE]
> Tibs syntax (and Nibs data model) allows any type as object keys, not just strings like in JSON


### `d` - Array

The `array` type is like list, except it includes an array of pointers before the payload to enable O(1) lookups.

This index is encoded via a secondary nibs pair where small is the byte width of the pointers and big is the number of entries.  This is followed by the pointers as offset distances from the start of the value segment.

The 4 sections are (`values`, `index`, `index-header`, `value-header`).

Examples:

Value | JSON | Nibs 
----- | ---- | ----
`[#1,2,3]` | N/A | `<d7 13 00 01 02 02 04 06>`

```lua
d7 --> Array(7)
  13 --> ArrayIndex(width=1,count=3)
    00 --> Pointer(0)
    01 --> Pointer(1)
    02 --> Pointer(2)
  02 --> ZigZag(2)
  04 --> ZigZag(4)
  06 --> ZigZag(6)
```

> [!NOTE]
> The `#` in the Tibs representation signifies the array should be indexed when converted to Nibs.

### `3`,`f` - Ref and Scope

The `Ref` type is used to reference into a userspace table of values.  The table is found by in the nearest `Scope` wrapping the current value.

Typically this is the outermost value in a nibs document so that all data can reuse the same refs array.

`Scope` is encoded like array, except the inner value comes before the index.

The 5 sections are (`targets`, `index`, `index-header`, `value`, `value-header`)

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
(
  "color", "fruits", "apple",
  [ { &0: "red", &1: [&2, "strawberry"] },
    { &0: "green", &1: [&2] },
    { &0: "yellow", &1: [&2, "banana"] } ]
)
```

This is about 25 bytes smaller than it would be encoded without refs.


Another example is encoding `[4,2,3,1]` using the refs `[1,2,3,4]`

The Tibs representation for this is:

```js
( 1, 2, 3, 4,
  [ &3, &1, &2, &0 ]
)
```

The Nibs representation is:

```lua
0e fc --> Scope-8(14)
  b4 --> List(4)
    33 --> Ref(3) -> Pointer(8) -> 4
    31 --> Ref(1) -> Pointer(6) -> 2
    32 --> Ref(2) -> Pointer(7) -> 3
    30 --> Ref(0) -> Pointer(5) -> 1
  14 --> ArrayIndex(width=1,count=4)
    00 --> Pointer(0) -> 1
    01 --> Pointer(1) -> 2
    02 --> Pointer(2) -> 3
    03 --> Pointer(3) -> 4
  02 --> ZigZag(2) = 1
  04 --> ZigZag(4) = 2
  06 --> ZigZag(6) = 3
  08 --> ZigZag(8) = 4
```

Note that refs are always zero indexed even if your language normally starts indices at 1.

Another example is the following (note one ref isn't used)

```js
( "dead", "beef", &1 )
```

```lua
fa --> Scope(10)
  31 --> Ref(1) -> "beef"
  12 --> ArrayIndex(width=1,count=2)
    00 --> pointer to header for `dead`
    03 --> pointer to header for `beef`
  a2 --> HexString(2)
    dead
  a2 --> HexString(2)
    beef
```

The larger ref example from above:

```js
// encoding with refs and refsscope
(
  "color", "fruits", "apple",
  [ { &0: "red", &1: [&2, "strawberry"] },
    { &0: "green", &1: [&2] },
    { &0: "yellow", &1: [&2, "banana"] } ]
)
```

Would encode like this:

```lua
4e fc --> Ref-8(78)
  35 bc --> List-8(53)
    14 cc --> Map-8(20)
      30 --> Ref(0)
      93 726564 --> "red"
      31 --> Ref(1)
      0c bc --> List-8(12)
        32 --> Ref(2)
        9a 73747261776265727279 --> "strawberry"
    ca --> Map(10)
      30 --> Ref(0)
      95 677265656e --> "green"
      31 --> Ref(1)
      b1 --> List(1)
        32 --> Ref(2)
    12 cc --> Map-8(18)
      30 --> Ref(0)
      96 79656c6c6f77 --> "yellow"
      31 --> Ref(1)
      b8 --> List(8)
        32 --> Ref(2)
        96 62616e616e61 --> "banana"
  13 --> ArrayIndex(width=1,count=3)
    00 --> Ptr(0) (header of "color")
    06 --> Ptr(6) (header of "fruits")
    0c --> Ptr(13) (header of "apple")
  95 636f6c6f72 --> "color"
  96 667275697473 --> "fruits"
  95 6170706c65 --> "apple"
```

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

## Types and SubTypes

For each encoded integer pair, the first small number is the type and the big number is it's parameter:

```c++
enum Type {

    // Inline types.
    Integer       = 0,  // big = zigzag encoded i64
    FloatingPoint = 1,  // big = binary encoding of float
    Simple        = 2,  // big = subtype
    Ref           = 3,  // big = index into runtime references table

    // slots 4-5 reserved for future inline types.
    // decoders can assume the nibs pair is all that needs skipping

    // slot 6 reserved for arbitrary future use
    // decoders can't assume behavior of these.

    // Tag Type - This is always followed by another nibs value
    // decoders must read the next value recursively when skipping
    Tag           = 7,  // big = index into runtime custom types table

    // Prefixed length types.
    Bytes         = 8,  // big = len
    String        = 9,  // big = len
    List          = 10, // big = len
    Map           = 11, // big = len
    Array         = 12, // big = len
    Trie          = 13, // big = len

    // slots 14-15 reserved for future prefixed length native types
    // decoders can assume they will always have big = len
};
```

The simple type has it's own subtype enum:

```c++
enum SubType {
    False     = 0,
    True      = 1,
    Null      = 2,
};
```

Some examples of encoding into nibs:

- `0` -> `Integer(0)` -> `0:0` -> `0000 0000`
- `-2` -> `Integer(3)` -> `0:3` -> `0000 0011`
- `42` -> `Integer(84)` -> `0:84` -> `0000 1100 01010100`
- `true` -> `Simple(1)` -> `2:1` -> `0010 0001`
- `&4` -> `Ref(4)` -> `3:4` -> `0011 0100`
- `2|false` -> `Tag(2) Simple(0)` -> `7:2 2:0` -> `0111 0010 0010 0000`

Note that it is possible to skip over any value by only reading the initial nibs pair (except for `tag` which needs to recursively skip the next value).

### ZigZag Integer

The `integer` type has `i64` range, but is encoded with zigzag encoding to take advantage of the smaller nibs representations for common values.

This maps negative values to positive values while going back and forth:

(0 = 0, -1 = 1, 1 = 2, -2 = 3, 2 = 4, -3 = 5, 3 = 6 ...)

```c
// Convert between signed value and `u64` bitfield representations.
uint64_t encodeZigZag(int64_t i) {
  return (i >> 63) ^ (i << 1);
}
int64_t decodeZigZag(uint64_t i) {
  return (i >> 1) ^ -(i & 1);
}
```

### Floating Point Number

The `float` type is stored as 64 bit IEEE floats bitcast to u64.

```c
// Convert between `f64` (double precision floating point) and `u64` bitfield representations.
uint64_t encodeDouble(double i) {
  return *(uint64_t*)(&i);
}
double decodeDouble(uint64_t i) {
  return *(double*)(&i);
}
```

### Simple SubType

Currently only `true`, `false`, and `null` are specified and the rest of the range is reserved.

### Reference

The `ref` type is used to reference into a userspace table of values.  This is commonly used as a means of compression to reduce the weight of repeated values commonly found in JSON workloads.  A suggested pattern is to include the refs as an `array` somewhere in the document so that the decoder knows where to find them.

```js
{ refs: [....],
  data: ... }
```

Note that it is up to the application and library exactly how the refs are found.  They don't have to be in the document at all and can reference a static dictionary or be provided via some side-channel at runtime.

It is recommended that APIs provide hooks for registering tags:

```typescript
declare class Nibs {
    // Register the refs one at a time
    registerReference(index: number, value: any);
    // Register the refs in bulk
    registerReferences(value: any[]);
}
```

### Custom Type Tag

The `tag` type is used for userspace custom data types.  It can attack a numerical type tag to any nibs value (even another tag if dfesired).  How this is interpreted is entirely up to the client library.  A suggested API may look like this:

```typescript
interface CustomType {
    name?: string // Used for enhanced text format to show names instead of integers.
    // Wrap the nibs encoded state and return the custom user type
    encode(nibs: any): T
    // Unwrap the custom user type and return a nibs serializable value
    decode(val: T): any
}

declare class Nibs {
    // Register one type at a time
    registerType(index: number, handler: CustomType)
    // Register all types in bulk
    registerTypes(handlers: CustomType[])
}
```

### String

The `string` type is assumed to be serialized as UTF-8 unicode.

Encoders should always emit normalized UTF-8 if possible.

Decoders are free to interpret bad encodings as makes sense for their application/language.

### Bytes

The `byte` type is a byte array for storing bulk binary octets.

### List

The `list` type is a ordered list of values.  It's encoded as zero or more nibs encoded values concatenated back to back.  These have O(n) lookup cost since the list of items needs to be scanned linearly.

For example `(1,2,3)` would be encoded as follows:

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

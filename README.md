# Nibs Serialization Format

Nibs is a new binary serialization format with the following set of priorities:

## Fast Random Access Reads

This format is designed to be read in-place (similar to cap'n proto) so that arbitrarily large documents can be read with minimal memory or compute requirements.  For example a 1 TiB mega nibs document could be read from a virtual block device where blocks are fetched from the network on-demand and the initial latency to start walking the data structure would be nearly instant.  Large documents could also be written to local NVMe drives and loaded to RAM using memmap.

To enable this random access, all values are either inline (just the nibs pair) or contain a prefix length so that a single indirection can jump to the next value.  Also some types like the [proposed `array` type](https://github.com/creationix/nibs/issues/4) enable O(1) lookup of arrays of any size.

Userspace types using the [proposed tags](https://github.com/creationix/nibs/issues/4) can enable O(1) misses and O(log n) hits for trees via userspace bloom filters and hash array mapped tries.

## Self Documenting

Nibs documents are similar to JSON in that the objects are self documenting (unlike protobuf that depends on implicit external schemas).  This works very well for dynamic programming environments like JavaScript and Lua or for replacing existing JSON workloads.

But if a developer chooses to also have schemas, it's possible to encode values as a nibs `list` and then the code would know what each positional value it.

## Compact on the Wire

Nibs tries to balance between compactness and simplicity and finds a nice middle ground.  Especially when combined with the [proposed `ref` type](https://github.com/creationix/nibs/issues/4) typical JSON payloads can be made considerably smaller.  Numbers are very compact, binary can be enbedded as-is without base64 or hex encoding, etc.

## Simple to Implement

One of the main goals of nibs vs existing formats is it aims to be simple implement.  It should be possible for a single developer with experience writing serilization libraries to have an initial working version very quickly so that new languages/tools can easily adopt it.  This also means that these libraries are likely to have no dependencies themselves keeping it lean.

This is a much simpler format than pretty much any of the existing formats except for JSON.

## Simple to Understand

Another goal is for the format itself to be simple to understand and think about.  The nibs-pair encoding is the same for all value types.  The types are grouped into similar behavior.  Anything complex is pushed out to userspace.

## Superset of JSON

Any value that can be encoded in JSON can also be encoded in nibs.  In this way it's similar to msgpack and cbor format, but it's much faster to read since it doesn't require parsing the whole document first.

There is also a [proposal to add a textual representation that is a superset of JSON](https://github.com/creationix/nibs/issues/3).  This would make it even easier to integrate into systems that use JSON or need textual representations of data (like config files or documentation).

# Format Specification

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
    Tuple         = 10, // big = len
    Map           = 11, // big = len
    Array         = 12, // big = len

    // slots 13-15 reserved for future prefixed length native types
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

### Tuple

The `tuple` type is a ordered list of values.  It's encoded as zero or more nibs encoded values concatenated back to back.  These have O(n) lookup cost since the list of items needs to be scanned linearly.

For example `(1,2,3)` would be encoded as follows:

```c
1010 0111 // Tuple(3)
0000 0010 // Integer(1)
0000 0100 // Integer(2)
0000 0110 // Integer(3)
```

### Array

The `array` type is like tuple, except it includes an array of pointers before the payload to enable O(1) lookups.

This index is encoded via a secondary nibs pair where small is the byte width of the pointers and big is the number of entries.  This is followed by the pointers as offset distances from the end of the index (the start of the list of values).

For example, the array `[1,2,3]` can be encoded as the following:

```c
1100 0111 // Array(len=7)
0001 0011 // IndexHeader(width=1,count=3)
 00000000 // Offset(0)
 00000001 // Offset(1)
 00000010 // Offset(2)
0000 0010 // Integer(1)
0000 0100 // Integer(2)
0000 0110 // Integer(3)
```

### Map

Map payloads are encoded as zero or more nibs encoded key and value pairs concatenated back to back.  These also have O(n) lookup costs.  It is recommended to use a userspace type via `tag` and probably `bytes` for more advanced data structures such as bloom filters or hash-array-mapped-tries.

For example, `{"name":"Nibs",true:false}` would be encoded as:

```c
1011 1100 // Map
 00001100 // (len=12)
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

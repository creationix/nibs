# Nibs Serialization Format

All multi-byte numbers in this spec are assumed to be little-endian.

In this document _"should"_ means that an implementation is recommended to work this way.
However _"must"_ means that it is not considered spec compliant without said behavior.

## Integer Pair Encoding

There are 5 possible encoding patterns depending on the size of the second number:

```js
xxxx 0yyy // (0-7)
xxxx 10yy yyyyyyyy // (8 - 1023)
xxxx 110y yyyyyyyy yyyyyyyy yyyyyyyy // (1024 - 32M-1)
xxxx 1110 yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy // (32M - 64P-1)
xxxx 1111 yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy yyyyyyyy // (64P - 16E-1)
```

Here the `x`s are a `u3` and the `y`s are semantically a `u64` using zero extension on the smaller numbers.

Encoders _should_ only use the smallest possible encoding for a given value.

Decoders _must_ accept all.

## Types and SubTypes

For each encoded integer pair, the first small number is the type and the big number is it's parameter:

```c++
enum Type {

    // Inline Types (no bytes followinf big)
    Integer    = 0, // big = num
    NegInteger = 1, // big = -num
    Float      = 2, // big = double cast to u64 as num
    Ref        = 3, // big = ref index

    // Length delimtied types (big is byte count following big)
    Binary     = 4, // big = length of byte array
    String     = 5, // big = length of byte array
    List       = 6, // big = length of byte array
    Map        = 7, // big = length of byte array
    Array      = 8, // big = length of byte array
    Trie       = 9, // big = length of byte array

    // 10,11,12 are reserved

    // Irregular Types
    Tag        = 13, // big = tag id, followed by exactly one value
    Stream     = 14, // big = tag id, followed by 0-n values
    End        = 15, // big = tag id or 0, marks end of stream
};

enum Ref {
    // Builtin Refs
    False = 0,
    True = 1,
    Nil = 2,
    NaN = 3,
    Infinity = 4,
    NegInfinity = 5,
    // 6 and 7 are reserved
    // Application defined refs start at 8
}
```

Some examples:

- `0` -> `Integer(0)` -> `0000 0000`
- `-2` -> `NegativeInteger(2)` - `0001 0010`
- `42` -> `Integer(42)` -> `0000 1100 00101010`
- `true` -> `Simple(1)` -> `0011 0001`

Note that it is possible to skip over any value by only reading the initial nibs pair.

### Integer and NegativeInteger

Encoders should use `Integer(0)` when encoding zero unless the application/language has both positive and negative zero.

Decoders should decode `NegativeInteger(0)` the same as `Integer(0)` unless the application/language has both values.

### Floating Point Number

Floating point numbers are stored as 64 bit IEEE floats cast to u64.

### Simple SubType

Currently only `true`, `false`, and `nil` and some special float values are specified and the rest of the range is reserved.

### String

Strings are assumed to be serialized as UTF-8 unicode.

Encoders should always emit normalized UTF-8 if possible.

Decoders are free to interpret bad encodings as makes sense for their application/language.

### Bytes

Byte arrays are for storing bulk binary octets.

### List

List payloads are encoded as zero or more nibs encoded values concatenated back to back.

### Map

Map payloads are encoded as zero or more nibs encoded key and value pairs concatenated back to back.

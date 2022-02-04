# Nibs Serialization Format

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
    Integer         = 0, // big = num
    NegativeInteger = 1, // big = -num
    FloatingPoint   = 2, // big = binary encoding of float
    Simple          = 3, // big = subtype

    // Prefixed length types.
    Bytes       = 4, // big = len
    String      = 5, // big = len
    List        = 6, // big = len
    Map         = 7, // big = len
};
```

Types 10-11 are reserved for future use.

The simple type has it's own subtype enum:

```c++
enum SubType {
    False     = 0,
    True      = 1,
    Nil       = 2,
    NaN       = 3,
    Infinity  = 4,
    -Infinity = 5,
};
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

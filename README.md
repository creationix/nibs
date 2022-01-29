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
    Simple          = 2, // big = subtype
    Ref             = 3, // big = referenceId

    // Prefixed length types.
    Bytes       = 4, // big = len
    String      = 5, // big = len
    List        = 6, // big = len
    Map         = 7, // big = len
    IndexedList = 8, // big = len
    IndexedMap  = 9, // big = len

    // Recursive type.
    Tag = 15, // big = customTag

};
```

Types 10-11 are reserved for future use.

The simple type has it's own subtype enum:

```c++
enum SubType {
    False = 0,
    True  = 1,
    Nil   = 2,
};
```

Some examples:

- `0` -> `Integer(0)` -> `0000 0000`
- `-2` -> `NegativeInteger(2)` - `0001 0010`
- `42` -> `Integer(42)` -> `0000 1100 00101010`
- `true` -> `Simple(1)` -> `0010 0001`

Note that it is possible to skip over any value by only reading the initial nibs pair except for `Tag(n)` where you have to recurse to the next value to know the full length.

### Integer and NegativeInteger

Encoders should use `Integer(0)` when encoding zero unless the application/language has both positive and negative zero.

Decoders should decode `NegativeInteger(0)` the same as `Integer(0)` unless the application/language has both values.

Integers outside the 64-bit range can be encoded using application-level tags.

### Floating Point Number

There is no native encoding for these in the spec yet, but applications can encode them using application-level tags.

### Simple SubType

Currently only `true`, `false`, and `nil` are specified and the rest of the range is reserved.  Use application-level tags for other values.

### Ref

Ref is used to reference cached values that are provided via some out of band mechanism.  For example a TCP stream using nibs values might also allow for caching/compressing nibs values by assigning then reference IDs.

### String

Strings are assumed to be serialized as UTF-8 unicode.

Encoders should always emit normalized UTF-8 if possible.

Decoders are free to interpret bad encodings as makes sense for their application/language.

### Bytes

Byte arrays are for storing bulk binary octets.  To attach semantic meaning, prefix with application level tags.

### List and IndexedList

List payloads are encoded as zero or more nibs encoded values concatenated back to back.  The difference in the indexed variant is the payload is prefixed by a second nibs pair and a pointer array.

TODO: document index format exactly.

### Map and IndexedMap

Map payloads are encoded as zero or more nibs encoded key and value pairs concatenated back to back.  The difference in the indexed variant is the payload is prefixed by a second nibs pair and a pointer trie.

TODO: document index format exactly.

### Tags

Tags allow applications to extend the format for their particular use case.  The format is to use other existing nibs types to encode their value (for example a Bytes value or a list or anything really) and then prefix it with a tag to assign it semantic meaning the application knows about.

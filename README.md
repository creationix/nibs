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

## Format Specifications

- [Binary Format](specs/binary-nibs-format.md)

## Implementations

- [JavaScript](js/README.md)
- [LuaJit](lua/README.md)
- Go (coming soon)

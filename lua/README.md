# Nibs for LuaJit

This is a generic nibs serializtion implementaion for any LuaJit runtime such as OpenResty or [Luvit](https://luvit.io/).

![Unit Tests](https://github.com/creationix/nibs/actions/workflows/test-lua.yaml/badge.svg)

## Install

If you're using luvit, install with lit:

```sh
lit install creationix/nibs
```

## Usage

```lua
local Nibs = require 'nibs'
```

### Encode

Encoding turns any lua value into a memory buffer.

```lua
local encoded = Nibs.encode { hello = "world" }
```

There are optional parameters that can be passed in after the value to tune the encoder.

```lua
Nibs.encode(value, options)
```

- `index_threshold = 16` is a threshold for when upgrade a `list` or `map` into an `array` or `trie` by generating an index.  A threshold of `0` means to always generate indexes, even for empty containers.  The default of `16` means any list with at least 16 entries or map with at least 16 keys will be upgraded.
- `trie_seed = 16` is the first xxhash64 seed to try when encoding a HAMT.  If this value is `nil` then a random integer is chosen each time, but a hard-coded integer is desirable for unit tests or anything wanting predictable encodings.
- `trie_optimize = 16` is how many seeds should be tried before picking the best one.  Larger values increase encoding time, but may decrease the encoded size.
- `ref_threshold = 16` is a threshold where repeated values are turned into a ref.  Lower values will create more refs and may save space overall, but eventually will become a net loss.  Cycles are always encoded as refs.

### Decode

Decoding turns any memory buffer into a nibs object.

```lua
local decoded = Nibs.decode(encoded)
```

### Lazy Reading

The lua implementation of nibs takes advantage of the `__index`, `__len`, `__ipairs`, and `__pairs` metamethods to make the decoded thin object appear as if it's a normal lua table, but only access and decode properties on demand.

This makes it possible, for example, to use `ffi` to `mmap` a massive nibs document from a local SSD, mount it using this library and randomly access the on-disk structure directly as if it was a local lua table.

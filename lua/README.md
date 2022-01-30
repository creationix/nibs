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

Encoding turns any lua value into a memory buffer.

```lua
local encoded = Nibs.encode { hello = "world" }
```

Decoding turns any memory buffer into a nibs object.

```lua
local decoded = Nibs.decode(encoded)
```

### Lazy Reading

The lua implementation of nibs takes advantage of the `__index`, `__len`, `__ipairs`, and `__pairs` metamethods to make the decoded thin object appear as if it's a normal lua table, but only access and decode properties on demand.

This makes it possible, for example, to use `ffi` to `mmap` a massive nibs document from a local SSD, mount it using this library and randomly access the on-disk structure directly as if it was a local lua table.

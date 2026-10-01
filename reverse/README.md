# Reverse Nibs

Reverse Nibs is a specially optimized variant of Nibs optimized for fast and low-overhead streaming encoding.

This implementation is further optimized to take JSON strings as input and output a stream of reverse nibs chunks.

It also has options to further optimize the output by allowing a list of ref values to be passed and a list of top level fields to keep.  This allows taking large legacy datasets and filtering them down to only the desired fields and deduplicating common values like object keys or string enums.

## Lua Example

```lua
local ReverseNibs = require 'rnibs'

local fruit_json = [[
  [
    { "color": "red",    "fruit": [ "apple", "strawberry" ] },
    { "color": "green",  "fruit": [ "apple" ] },
    { "color": "yellow", "fruit": [ "apple", "banana" ] }
  ]
]]

local encoded, err = ReverseNibs.convert(fruit_json, {
    -- Automatically find the duplicated strings `color`, `fruit`, and `apple`.
    dups = ReverseNibs.find_dups(fruit_json),
    -- Force index for the toplevel array for testing purposes
    indexLimit = 3,
})
```

## Run Tests

```sh
# Ih the `reverse` folder run the following
ls test-*.lua | xargs -l luvit
```

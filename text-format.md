Nibs is primarily a binary format to enable fast parsing and random access.  But sometimes it's really nice to have a textual way to visualize or specify the data.

This text format is a superset of JSON extended to support all of nibs's types:

- `Integer` and `NegativeInteger` are both stored in JSON as either decimal, same as JSON.
- `FloatingPoint` is stored as decimal, but always includes the decimal and at least 1 digit on both sides of it.
- `Bytes` is stored as `<XXXXXX>` where `XXXXXX` is the raw bytes encoded in hexadecimal (uppercase or lowercase allowed)
- `String` is stored as normal JSON string syntax.
- `List` is stored as normal JSON array syntax.
- `Map` is stored as normal JSON object syntax.
- `False` and `True` are stored JSON boolean
- `Nil` is stored as JSON null
 -`NaN`, `Infinity`, `-Infinity` are stored as `NaN`, `Infinity`, and `-Infinity`

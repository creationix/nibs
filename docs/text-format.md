# Nibs Text Format

Nibs documents can be represented in a textual format.  While this format isn't as fast to parse and takes up more space, it has some various use cases that make it very handy.

## Full Nibs Semantics

The nibs text format can fully encode any nibs document and allow round-tripping back and forth without any data changing.

- Nibs `integer` is encoded as decimal text.
- Nibs `float` is encoded as JSON number, but always has the decimal point and at least one digit of precision.
  - Special Nibs `float` values are encoded as `inf`, `-inf`, and `nan`.
- Nibs `boolean` is encoded as `true` or `false`.
- Nibs `null` is encoded as `null`.
- Nibs `binary` is encoded as `<XXXXXX>` where `XX` is a byte in hexadecimal.
- Nibs `string` is encoded the same way as JSON `string`.
- Nibs `map` is encoded the same way as JSON `object` except any value is allowed for keys (not just strings).
- Nibs `array` is encoded the same way as JSON `array`.
- Nibs `tuple` is encoded like array, except `(` and `)` are used in place of the square brackets.
- Nibs `ref` is encoded as `&` followed by a decimal ref index.
- Nibs `tag` is encoded as `!` followed by a decimal tag index and then a nibs text value.

## Made for Humans

The binary nibs format is optimized for machines, but this text format is for humans.  As such it adds a couple of nice things to make it easier to write and maintain by hand.

- JS style like and block comments.
- Optional trailing comma in lists.
- Insignificant whitespace.

## JSON Interoperability

One property of this format's design is that it is a superset of JSON.  This means that the nibs text format decoder can consume JSON documents since they are all also valid nibs-text documents!

- JSON `number` with no decimal becomes Nibs `integer`
- JSON `number` with a decimal becomes Nibs `float`
- JSON `object` becomes Nibs `map`
- JSON `array` becomes Nibs `array` (index is generated)
- `null`, `string` and `boolean` are the same in both

Also the nibs-text encoder should have an option to limit to the JSON subset.  This has some lossy properties:

- Nibs `integer` becomes JSON `number`
- Nibs `float` becomes JSON `number` that always have a decimal point
- Nibs `binary` becomes hex encoded JSON `string`
- Nibs `array` and `tuple` becomes JSON `array` (tuples get upgraded to arrays)
- Nibs `map` becomes JSON `object` (any non-string keys are encoded in nibs-text as strings)
- Nibs `tag` is discarded
- Nibs `ref` is dereferenced
- `null`, `string` and `boolean` are the same in both

## Embedding in Restricted Storage

Nibs' normal binary format cannot be used in places that don't support arbitrary binary data.  But using the textual representation of a nibs document allows it to be stored in many places:

- Inline in source code
- Configuration files
- HTTP header values (as ASCII)
- Web LocalStorage
- JavaScript strings
- As a debugging tool to log values to the console.
- etc...

*Note*: When storing nibs in HTTP header values to make sure to encode it in ASCII mode by escaping all non-ascii characters using the JSON `\uXXXX` syntax.

## Proposed APIs

When implementing a nibs library, this is a recommended API for the nibs-text portion:

```ts
declare class Nibs {

  // Encode a live nibs value into it's string representation
  // The `ascii` option escapes UTF-8 characters.
  // The `json` option toggles between JSON compability and full
  // data fidelity.
  toString(value: any, opts?: { ascii: boolean, json: boolean }): string;

  // Decode a nibs-text value into a live nibs value.
  fromString(str: string): any;

}
```

## Railroad Diagrams

![array](./array.svg)

![binary](./binary.svg)

![float](./float.svg)

![integer](./integer.svg)

![map](./map.svg)

![ref](./ref.svg)

![string](./string.svg)

![tag](./tag.svg)

![tuple](./tuple.svg)

![value](./value.svg)

![whitespace](./whitespace.svg)

# Nibs for JavaScript

This is a generic nibs serializtion implementaion for any modern JavaScript runtime.

![Unit Tests](https://github.com/creationix/nibs/actions/workflows/test-js.yaml/badge.svg)

[![npm version](https://badge.fury.io/js/nibs.svg)](https://badge.fury.io/js/nibs)

## Install

```sh
npm i nibs
```

## Usage

Nibs is packaged as an ES module.  You can import the exports individually:

```js
import { 
    encode, // JS Value -> Nibs Uint8Array
    decode, // Nibs Uint8Array -> Lazy JS Value
} from 'nibs'
```

Or you can grab the entire namespace:

```js
import * as Nibs from 'nibs'
```

Encoding turns any supported JS value into a memory buffer.

```js
const encoded = Nibs.encode({ hello: "world" })
```

Decoding turns any memory buffer into a nibs object.

```js
const decoded = decode(encoded)

// All nibs maps decode to JavaScript maps.
// It doesn't matter of you used a map or an object when encoding.
// I'm considering a variant of this library that decodes to JS objects instead.
const hello = decoded.get('hello')
```

### Lazy Reading

The JS implementation of nibs takes advantage getter functions to make objects and arrays appear like normal, but only decode when properties are actually read.  It will cache the result as you traverse an object and replace the getter with the decoded value.

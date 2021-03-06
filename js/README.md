# Nibs for JavaScript

This is a generic nibs serializtion implementaion for any modern JavaScript runtime.

![Unit Tests](https://github.com/creationix/nibs/actions/workflows/test-js.yaml/badge.svg)

[![npm version](https://badge.fury.io/js/nibs.svg)](https://badge.fury.io/js/nibs)

## Install

```sh
npm i nibs
```

## Usage

```js
import { encode, decode } from 'nibs'
```

Encoding turns any supported JS value into a memory buffer.

```js
const encoded = encode { hello: "world" }
```

Decoding turns any memory buffer into a nibs object.

```js
const decoded = decode(encoded)
```

### Lazy Reading

The JS implementation of nibs takes advantage getter functions to make objects and arrays appear like normal, but only decode when properties are actually read.  It will cache the result as you traverse an object and replace the getter with the decoded value.

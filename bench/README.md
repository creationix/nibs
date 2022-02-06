# Nibs Benchmark

Nibs is meant for read heavy workloads.

This benchmark uses the [corgis dataset](https://corgis-edu.github.io/corgis/json/) to create a single massive JSON file of all the types combined. The resulting file is 165 MiB of JSON.

## Nibs Encoding

Nibs encoding is a lot slower than JSON in JavaScript for large datasets.

- V8 `JSON.stringify` - 48.1 encodes per minute (1.2s each)
- V8 `Nibs.encode` - 1.35 encodes per minute (44s each)

## Nibs Decoding

Nibs decoding is nearly instant and almost 6000x faster than JSON for this giant dataset.

- V8 `JSON.parse` - 56.6 decodes per minute (1,060 ms each)
- V8 `Nibs.decode` - 317,903 decodes per minute (0.19 ms each)

## Nibs Walking

Part of what makes nibs decoding so fast is it's lazy and so you pay the cost when walking the resulting object. But thanks to the memoizing in JS, it's basically free for repeated values and same speed of decode for uncached values.

- V8 Nibs Walk - 49,6812,275 walks per minute (0.12 μs each)

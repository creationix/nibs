# Nibs Benchmark

Nibs is meant for read heavy workloads.

This benchmark uses the [corgis dataset](https://corgis-edu.github.io/corgis/json/) to create a single massive JSON file of all the types combined. The resulting file is 165 MiB of JSON.

## Nibs Decoding

Nibs decoding is nearly instant and almost 6000x faster than JSON for this giant dataset.

- V8 `JSON.parse` - 56.6 decodes per minute (1,060 ms each)
- V8 `Nibs.decode` - 317,903 decodes per minute (0.19 ms each)
- Luvit `JSON.decode` - 11.77 decoded per minute (5.1s each)
- Luvit `Nibs.decode` - 903,090,960 decodes per minute (66 ns each)

## Nibs Walking

Part of what makes nibs decoding so fast is it's lazy and so you pay the cost when walking the resulting object. But thanks to the memoizing in JS, it's basically free for repeated values and same speed of decode for uncached values.

- V8 Nibs Walk - 49,6812,275 walks per minute (0.12 μs each)

## Nibs Encoding

Nibs is intended to be optimied for read-heavy workloads, but here are numbers for encodes:

- V8 `JSON.stringify` - 48.1 encodes per minute (1.2s each)
- V8 `Nibs.encode` - 1.35 encodes per minute (44s each)
- Luvit `JSON.encode` - 7.15 encodes per minute (8.3s each)
- Luvit `Nibs.encode` - 9.09 encodes per minute (6.6s each)

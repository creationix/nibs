# Simple HAMT

This simple data structure is based on [Hash Array Mapped Tries](https://idea.popcount.org/2012-07-25-introduction-to-hamt/)

This simplified data model assumes that the keys have already been hashed to a stream of bits and that the values are simple offset pointers.

The entries in this format are a fixed width power of 2 that is used for both bitfields and pointers.

## Inserting an Entry

Let's consider a 4-bit wide example with 4 entries.  The full hashes aren't shown since we only need 4 bits for this example.  The targets are unsigned 3-bit integers (used as offsets into some other memory)

```c++
// key/value lookup 
// from bitstream (hash of key)
// to u3 (offset to value)
...0101 -> 010
...0011 -> 101
...1010 -> 011
...1011 -> 000
```

To create the trie, first start with an empty node with all zeroes for the bitfield.

```c++
// ...xx Root
0000 // Bitfield []
```

Now we want to insert `...0101 -> 010`.  Since this is the root trie node, we want the 2 least significant bits `01`.  These are inserted by setting the bitfield bit for `01` and appending the pointer.  Since this is a leaf pointer, we shift in a 1 on the least significant side to tag the pointer.

```c++
// ...xx Root
0010 // Bitfield [01]
0101 // 01: Leaf ...0101 -> 010
```

In the comment, the full hash `...0101` is mentioned, this will be needed later by the implementation in case another insert collides with this prefix.  But in the final encoding, the full hashes are not kept in this data structure (the application can include them in the payload that the offset points to)

Now repeat to insert `...0011 -> 101`:

```c++
// ...xx Root
1010 // Bitfield [01,11]
0101 // 01: ...0101 -> 010 Leaf
1011 // 11: ...0011 -> 101 Leaf
```

Repeat again to insert `...1010 -> 011`

```c++
// ...xx Root
1110 // Bitfield [01,10,11]
0101 // 01: ...0101 -> 010 Leaf
0111 // 10: ...1010 -> 011 Leaf
1011 // 11: ...0011 -> 101 Leaf
```

The next insert is a bit harder since there is already an entry for the `11` prefix pattern.  So first we need to promote the existing value to a sub node by replacing the leaf pointer with a branch pointer, creating a new empty node and inserting the value again using the next two prefix bits in it's hash.

```c++
// ...xx Root
1110 // Bitfield [01,10,11]
0101 // 01: ...0101 -> 010 Leaf
0111 // 10: ...1010 -> 011 Leaf
0000 // 11: -> 000 Branch
// xx11 Branch
0001 // Bitfield [00]
1011 // 00: ...0011 -> 101 Leaf
```

Now that the there is a branch for the `...11` prefix in the root node and our desired prefix is open in this branch node, we can finally insert the last value `...1011 -> 000`.

```c++
// ...xx Root
1110 // Bitfield [01,10,11]
0101 // 01: ...0101 -> 010 Leaf
0111 // 10: ...1010 -> 011 Leaf
0000 // 11: -> 000 Branch
// xx11 Branch
0101 // Bitfield [00,10]
1011 // 00: ...0011 -> 101 Leaf
0001 // 10: ...1011 -> 000 Leaf
```

And there we have it, at 7 entries * 4 bits, we have a HAMT mapping with 4 entries.

## Indexing an Entry

Now let's consider how to consume this data structure.  Suppose we want to index `...0011`:

First we take the first two bits (least significant) as a prefix and lookup in the root bitfield.

```c++
static int bits_per_level = 2; // 4-bit wide bitfield
static int mask = (1 << bits_per_level) - 1; // 0b11

int get_prefix(int hash, int level) {
  return (hash >> (bits_per_level * level)) & mask;
}
```

Using this formula: `get_prefix(...0011, 0) -> 11`

We then check if the root bitfield has an entry for `11`.

```c++
bool has_prefix(int bitfield, int prefix) {
    return (bitfield & (1 << prefix)) > 0
}
```

Using this formula `has_prefix(1011, 11) -> true`, we see the pointer exists at this level.

Then we need to calculate which pointer it is by counting 1 bits.

```c++
int get_index(int bitfield, int prefix) {
    int mask = (1 << prefix) - 1;
    return popcnt(bitfield & mask)
}
```

Using this formula `get_index(1011, 11) -> 2` we learn that our pointer is the 3rd pointer

Decoding this pointer `0000` we see that it's an internal branch pointer at offset 0 so we increment 0 (4-bit words) to find the next bitfield and recurse.

Now we need to get the second prefix using `get_prefix(...0011, 1) -> 00`.

Then we check if it's in the bitfield using `has_prefix(0101, 00) -> true`

Then we get the pointer offset using `get_index(0101, 00) -> 0`

Which gives us the pointer `1011` which decoded is a leaf pointer with `101`!

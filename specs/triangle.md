# Triangle Encoding

```lua
bitstats = { 
   [0] = 479,
   [1] = 43786,
   [2] = 54276,
   [3] = 46792,
   [4] = 40542,
   [5] = 59089,
   [6] = 25338,
   [7] = 64306,
   [8] = 7138,
   [9] = 1972,
  [10] = 1989,
  [11] = 1739,
  [12] = 198,
  [13] = 272,
  [14] = 334,
  [15] = 443,
  [16] = 494,
  [17] = 709,
  [18] = 763,
  [19] = 224, 
  [20] = 111,
  [21] = 79,
  [22] = 34,
  [23] = 9,
  [24] = 4,
  [25] = 5,
  [26] = 1,
}
```

```c

varint4 - stores u32 values using 1-5 bytes
  0xxx ...[0](3-bit)
  10xx ...[1](10-bit)
  110x ...[2](17-bit)
  1110 ...[3](24-bit)
  1111 ...[4](32-bit)

varint4x2 - stores u32 values using 1-9 bytes
  0xxx ...[0](3-bit)
  10xx ...[2](18-bit)
  110x ...[4](33-bit)
  1110 ...[6](48-bit)
  1111 ...[8](64-bit)

varint4p2 - stores u64 values using 1-9 bytes
  0xxx ...[0](3-bit)
  10xx ...[1](10-bit)
  110x ...[2](17-bit)
  1110 ...[4](32-bit)
  1111 ...[8](64-bit)

varint4fit - stores u64 values using 1-9 bytes
  0xxx ...[0](3-bit)
  10xx ...[1](10-bit)
  110x ...[3](25-bit)
  1110 ...[7](56-bit)
  1111 ...[8](64-bit)

varint8 - stores u64 values using 1-9 bytes
  0xxxxxxx ...[0](7-bit)
  10xxxxxx ...[1](14-bit)
  110xxxxx ...[2](21-bit)
  1110xxxx ...[3](28-bit)
  11110xxx ...[4](35-bit)
  111110xx ...[5](42-bit)
  1111110x ...[6](49-bit)
  11111110 ...[7](56-bit)
  11111111 ...[8](64-bit)

varint16 - stores u128 values using 1-33 bytes
  0xxxxxxxxxxxxxxx ...[0](15-bit)
  10xxxxxxxxxxxxxx ...[1](22-bit)
  110xxxxxxxxxxxxx ...[2](29-bit)
  1110xxxxxxxxxxxx ...[3](36-bit)
  11110xxxxxxxxxxx ...[4](43-bit)
  111110xxxxxxxxxx ...[5](50-bit)
  1111110xxxxxxxxx ...[6](57-bit)
  11111110xxxxxxxx ...[7](64-bit)
  111111110xxxxxxx ...[8](71-bit)
  1111111110xxxxxx ...[9](78-bit)
  11111111110xxxxx ...[10](85-bit)
  111111111110xxxx ...[11](92-bit)
  1111111111110xxx ...[12](99-bit)
  11111111111110xx ...[13](106-bit)
  111111111111110x ...[14](113-bit)
  1111111111111110 ...[15](120-bit)
  1111111111111111 ...[16](128-bit)

varint16x2 - stores u256 values using 1-33 bytes
  0xxxxxxxxxxxxxxx ...[0](15-bit)
  10xxxxxxxxxxxxxx ...[2](30-bit)
  110xxxxxxxxxxxxx ...[4](45-bit)
  1110xxxxxxxxxxxx ...[6](60-bit)
  11110xxxxxxxxxxx ...[8](75-bit)
  111110xxxxxxxxxx ...[10](90-bit)
  1111110xxxxxxxxx ...[12](105-bit)
  11111110xxxxxxxx ...[14](120-bit)
  111111110xxxxxxx ...[16](135-bit)
  1111111110xxxxxx ...[18](150-bit)
  11111111110xxxxx ...[20](165-bit)
  111111111110xxxx ...[22](180-bit)
  1111111111110xxx ...[24](195-bit)
  11111111111110xx ...[26](210-bit)
  111111111111110x ...[28](225-bit)
  1111111111111110 ...[30](240-bit)
  1111111111111111 ...[32](256-bit)



1xxxxxxx bytes(type: OCTETS | UTF8 | HEX | CHAIN, length: varint5) ... ...
01xxxxxx container(type: LIST | MAP, length: varint5) ... ...
001xxxxx ref(index: varint5) ...
0001xxxx integer(base: zigzag varint4) ...
0001xxxx decimal(sign: POS|NEG, exponent: 8BIT|16BIT, base: 8BIT|16BIT|32BIT|56BIT) ... ...
0000001x boolean(value: FALSE | TRUE)
00000001 xxxxxxxx ?
00000000 null

(3) integer:
(5)   base: signed

(3) simple:
(2)   value: FALSE | TRUE | NULL | REF
(3)   ref-index: unsigned

(3) decimal:
(1)   sign: POSITIVE | NEGATIVE
(2)   exponent: signed
(2)   base: unsigned

(3) bytes:
(2)   representation: OCTETS | UTF8 | BINARY | HEX | BASE58 | BASE64 | BASE64URL
(3)   length: unsigned
[followed by bytes]

(3) container(
(2)   representation: LIST | MAP | ARRAY | TRIE | REFSCOPE
(3)   length: unsigned
[followed by bytes]

indexedContainer(
    representation: 
    pointer-width: unsigned
    count: unsigned
    length: unsigned
) [followed by bytes]

sparseArray(
    index-width: unsigned
    pointer-width: unsigned
    count: unsigned
    length: unsigned
) [followed by bytes]



```

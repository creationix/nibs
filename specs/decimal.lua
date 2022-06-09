--[[

varint4
  xxxx 0-11
  1100 8BIT ...
  1101 16BIT ...
  1110 32BIT ...
  1111 64BIT ...

varint5
  xxxxx 0-59
  11100 8BIT ...
  11101 16BIT ...
  11110 32BIT ...
  11111 64BIT ...

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



]]

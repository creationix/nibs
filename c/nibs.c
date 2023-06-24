#include "nibs.h"
#include <math.h>
#include "arena.h"
#include "slice.h"
#include <stddef.h>
#include <string.h>

static slice_node_t* alloc_slice(arena_t* arena, size_t len) {
  slice_node_t* node = arena_alloc(arena, sizeof(*node) + len);
  node->next = NULL;
  node->len = len;
  return node;
}

slice_node_t* nibs_alloc_pair(arena_t* arena,
                                unsigned int small,
                                uint64_t big,
                                bool is_container) {
  size_t extra = is_container ? big : 0;
  if (big < 12) {
    slice_node_t* node = alloc_slice(arena, 1 + extra);
    node->data[0] = (small << 4) | big;
    return node;
  }
  if (big < 0x100) {
    slice_node_t* node = alloc_slice(arena, 2 + extra);
    node->data[0] = (small << 4) | 0xc;
    node->data[1] = big;
    return node;
  }
  if (big < 0x10000) {
    slice_node_t* node = alloc_slice(arena, 3 + extra);
    node->data[0] = (small << 4) | 0xd;
    *(uint16_t*)(&node->data[1]) = big;
    return node;
  }
  if (big < 0x100000000) {
    slice_node_t* node = alloc_slice(arena, 5 + extra);
    node->data[0] = (small << 4) | 0xe;
    *(uint32_t*)(&node->data[1]) = big;
    return node;
  }
  slice_node_t* node = alloc_slice(arena, 9 + extra);
  node->data[0] = (small << 4) | 0xf;
  *(uint64_t*)(&node->data[1]) = big;
  return node;
}

static uint64_t zigzag_encode(int64_t num) {
  return (num >> 63) ^ (num << 1);
}

// static int64_t zigzag_decode(uint64_t num) {
//   return (num >> 1) ^ -(num & 1);
// }

union float_converter {
  uint64_t i;
  double f;
};

static uint64_t float_encode(double num) {
  // Hard code all NaNs to match V8 JavaScript
  if (isnan(num)) {
    return 0x7ff8000000000000;
  }
  return ((union float_converter){.f = num}).i;
}

// static double float_decode(uint64_t num) {
//   return ((union float_converter){.i = num}).f;
// }

slice_node_t* nibs_encode_integer(arena_t* arena, int64_t num) {
  return nibs_alloc_pair(arena, NIBS_ZIGZAG, zigzag_encode(num), false);
}

slice_node_t* nibs_encode_double(arena_t* arena, double num) {
  return nibs_alloc_pair(arena, NIBS_FLOAT, float_encode(num), false);
}

slice_node_t* nibs_encode_boolean(arena_t* arena, bool val) {
  return nibs_alloc_pair(arena, NIBS_SIMPLE, val ? NIBS_TRUE : NIBS_FALSE, false);
}

slice_node_t* nibs_encode_null(arena_t* arena) {
  return nibs_alloc_pair(arena, NIBS_SIMPLE, NIBS_NULL, false);
}

// // Check for even number of lowercase hex inputs.
// bool is_hex(const char* str, size_t len) {
//   if (len == 0 || len % 2 != 0) {
//     return false;
//   }
//   for (size_t i = 0; i < len; i++) {
//     uint8_t b = str[i];
//     if (b < '0' || (b > '9' && b < 'a') || b > 'f') {
//       return false;
//     }
//   }
//   return true;
// }

// static slice_node_t* nibs_encode_hex(arena_t* arena, const char* str, size_t len) {
//   len >>= 1;
//   slice_node_t* node = nibs_alloc_pair(arena, NIBS_HEXSTRING, len, true);
//   size_t offset = node->len - len;
//   for (size_t i = 0; i < len; i++) {
//     node->data[offset + i] = (hex_to_int(str[i * 2]) << 4) |
//                               hex_to_int(str[i * 2 + 1]);
//   }
//   return node;
// }

// slice_node_t* nibs_encode_string(arena_t* arena, const char* str, size_t len) {
//   if (!is_hex(str, len)) {
//     return encode_hex(arena, str, len);
//   }
//   slice_node_t* node = nibs_alloc_pair(arena, NIBS_UTF8, len, true);
//   size_t offset = node->len - len;
//   memcpy(node->data + offset, str, len);
//   return node;
// }


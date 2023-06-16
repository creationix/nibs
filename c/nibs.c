#include "nibs.h"


struct slice_node {
  struct slice_node* next;
  size_t len;
  uint8_t data[];
};

typedef struct slice_node node_t;

static node_t* alloc_slice(arena_t* arena, size_t len, node_t* next) {
  node_t* node = arena_alloc(arena, sizeof(*node) + len);
  node->next = next;
  node->len = len;
  return node;
}

static node_t* alloc_pair(arena_t* arena,
                          unsigned int small,
                          uint64_t big,
                          node_t* next) {
  if (big < 12) {
    node_t* node = alloc_slice(arena, 1, next);
    node->data[0] = (small << 4) | big;
    return node;
  }
  if (big < 0x100) {
    node_t* node = alloc_slice(arena, 2, next);
    node->data[0] = (small << 4) | 0xc;
    node->data[1] = big;
    return node;
  }
  if (big < 0x10000) {
    node_t* node = alloc_slice(arena, 3, next);
    node->data[0] = (small << 4) | 0xd;
    *(uint16_t*)(&node->data[1]) = big;
    return node;
  }
  if (big < 0x100000000) {
    node_t* node = alloc_slice(arena, 5, next);
    node->data[0] = (small << 4) | 0xe;
    *(uint32_t*)(&node->data[1]) = big;
    return node;
  }
  node_t* node = alloc_slice(arena, 9, next);
  node->data[0] = (small << 4) | 0xf;
  *(uint64_t*)(&node->data[1]) = big;
  return node;
}

static uint64_t zigzag_encode(int64_t num) {
  return (num >> 63) ^ (num << 1);
}

static int64_t zigzag_decode(uint64_t num) {
  return (num >> 1) ^ -(num & 1);
}

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

static double float_decode(uint64_t num) {
  return ((union float_converter){.i = num}).f;
}

node_t* encode_integer(arena_t* arena, int64_t num, node_t* next) {
  return alloc_pair(arena, NIBS_ZIGZAG, zigzag_encode(num), next);
}

node_t* encode_double(arena_t* arena, double num, node_t* next) {
  return alloc_pair(arena, NIBS_FLOAT, float_encode(num), next);
}

node_t* encode_boolean(arena_t* arena, bool val, node_t* next) {
  return alloc_pair(arena, NIBS_SIMPLE, val ? NIBS_TRUE : NIBS_FALSE, next);
}

node_t* encode_null(arena_t* arena, node_t* next) {
  return alloc_pair(arena, NIBS_SIMPLE, NIBS_NULL, next);
}

// Check for even number of lowercase hex inputs.
static bool is_hex(const char* str, size_t len) {
  if (len == 0 || len % 2 != 0) {
    return false;
  }
  for (int i = 0; i < len; i++) {
    uint8_t b = str[i];
    if (b < 0x30 || (b > 0x39 && b < 0x61) || b > 0x66) {
      return false;
    }
  }
  return true;
}

static int fromhex(uint8_t c) {
  return c < 0x40 ? c - 0x30 : c - 0x61 + 10;
}

static void hexcpy(uint8_t* dest, const uint8_t* source, size_t len) {
  for (int i = 0; i < len; i++) {
    dest[i] = (fromhex(source[i * 2]) << 4) | fromhex(source[i * 2 + 1]);
  }
}

// Encode a null terminated c-string that's already UTF-8 encoded
node_t* encode_const_string(arena_t* arena, const char* str, node_t* next) {
  size_t len = strlen(str);
  node_t* body;
  if (len) {
    if (is_hex(str, len)) {
      len >>= 1;
      body = alloc_slice(arena, len, next);
      hexcpy(body->data, (uint8_t*)str, len);
      return alloc_pair(arena, NIBS_HEXSTRING, len, body);
    }
    body = alloc_slice(arena, len, next);
    memcpy(body->data, str, len);
    return alloc_pair(arena, NIBS_UTF8, len, body);
  }
  return alloc_pair(arena, NIBS_UTF8, 0, next);
}

// Encode a null terminated c-string that's already UTF-8 encoded
node_t* encode_hex_bytes(arena_t* arena, const char* str, node_t* next) {
  size_t len = strlen(str);
  assert(len % 2 == 0);
  len >>= 1;
  node_t* body = alloc_slice(arena, len, next);
  hexcpy(body->data, (uint8_t*)str, len);
  return alloc_pair(arena, NIBS_BYTES, len, body);
}

void dump_chain(node_t* node) {
  while (node) {
    printf("(ptr = %p, len = %zu) ", node->data, node->len);
    node = node->next;
    if (node) {
      printf("-> ");
    }
  }
  printf("\n");
}

node_t* flatten(arena_t* arena, node_t* node) {
  // Calculate total size needed to encode
  size_t len = 0;
  node_t* current = node;
  node_t* tail = NULL;
  int count = 0;
  while (current) {
    len += current->len;
    tail = current->next;
    current = current->next;
    count++;
  }
  if (count == 1) {
    return node;
  }
  dump_chain(node);
  printf("flatten: %zu\n", len);

  node_t* combined = alloc_slice(arena, len, tail);
  uint8_t* ptr = combined->data;

  current = node;
  while (current) {
    memcpy(ptr, current->data, current->len);
    ptr += current->len;
    current = current->next;
  }

  return combined;
}

static node_t* encode_list(arena_t* arena,
                           int count,
                           node_t** items,
                           node_t* next) {
  size_t total = 0;
  node_t* first = NULL;
  node_t* last = NULL;
  for (int i = 0; i < count; i++) {
    node_t* item = items[i];
    if (item) {
      if (!first) {
        first = item;
      }
      if (last) {
        last->next = item;
      }
      while (item) {
        total += item->len;
        last = item;
        item = item->next;
      }
    }
  }
  if (last) {
    last->next = next;
  }
  return alloc_pair(arena, NIBS_LIST, total, first);
}

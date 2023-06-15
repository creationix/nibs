#define _GNU_SOURCE
#include <assert.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>

#include <stdio.h>

#include "nibs.h"

#define ARENA_SIZE 0x40000000  // 1 GiB

struct arena {
  void* start;
  void* current;
  void* end;
};
typedef struct arena arena_t;

static void arena_init(arena_t* arena) {
  arena->start = mmap(NULL, ARENA_SIZE, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  assert(arena->start);
  arena->current = arena->start;
  arena->end = arena->start + ARENA_SIZE;
}

static void arena_deinit(arena_t* arena) {
  assert(arena->start);
  munmap(arena->start, ARENA_SIZE);
  arena->start = NULL;
  arena->current = NULL;
}

static void* arena_alloc(arena_t* arena, size_t len) {
  assert(arena->current);
  void* ptr = arena->current;
  arena->current += len;
  assert(arena->current < arena->end);
  return ptr;
}

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

static node_t* hex_str(arena_t* arena, const char* str) {
  size_t len = strlen(str);
  assert(len % 2 == 0);
  len >>= 1;
  node_t* buf = alloc_slice(arena, len, NULL);
  hexcpy(buf->data, (const uint8_t*)str, len);
  return buf;
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

bool slice_equal(arena_t* arena, node_t* actual, node_t* expected) {
  if (actual->next)
    actual = flatten(arena, actual);
  if (expected->next)
    expected = flatten(arena, expected);
  printf("expected: ");
  for (int i = 0; i < expected->len; i++) {
    printf("%02x", expected->data[i]);
  }
  printf("\nactual:   ");
  for (int i = 0; i < actual->len; i++) {
    if (i < expected->len && actual->data[i] != expected->data[i]) {
      printf("\033[31m%02x\033[0m", actual->data[i]);
    } else {
      printf("%02x", actual->data[i]);
    }
  }
  printf("\n");

  if (expected->len != actual->len) {
    printf("Expected length %ld, but got %ld\n", expected->len, actual->len);
    return false;
  }
  for (int i = 0; i < actual->len; i++) {
    if (expected->data[i] != actual->data[i])
      return false;
  }
  return true;
}

#define assert_equal_integer(arena, actual, expected)            \
  assert(slice_equal(arena, encode_integer(arena, actual, NULL), \
                     hex_str(arena, expected)))

#define assert_equal_double(arena, actual, expected)            \
  assert(slice_equal(arena, encode_double(arena, actual, NULL), \
                     hex_str(arena, expected)))

#define assert_equal_boolean(arena, actual, expected)            \
  assert(slice_equal(arena, encode_boolean(arena, actual, NULL), \
                     hex_str(arena, expected)))

#define assert_equal_null(arena, expected) \
  assert(slice_equal(arena, encode_null(arena, NULL), hex_str(arena, expected)))

#define assert_equal_string(arena, actual, expected)                  \
  assert(slice_equal(arena, encode_const_string(arena, actual, NULL), \
                     hex_str(arena, expected)))

#define assert_equal_bytes(arena, actual, expected)                  \
  assert(slice_equal(arena, encode_hex_bytes(arena, actual, NULL), \
                     hex_str(arena, expected)))

int main() {
  assert(zigzag_encode(0) == 0);
  assert(zigzag_encode(-1) == 1);
  assert(zigzag_encode(1) == 2);
  assert(zigzag_encode(0x7fffffffffffffff) == 0xfffffffffffffffe);
  assert(zigzag_encode(-0x8000000000000000) == 0xffffffffffffffff);

  assert(zigzag_decode(0) == 0);
  assert(zigzag_decode(1) == -1);
  assert(zigzag_decode(2) == 1);
  assert(zigzag_decode(0xfffffffffffffffe) == 0x7fffffffffffffff);
  assert(zigzag_decode(0xffffffffffffffff) == -0x8000000000000000);

  assert(float_encode(-0.1) == 0xbfb999999999999a);
  assert(float_encode(0.1) == 0x3fb999999999999a);
  assert(float_encode(-1.1) == 0xbff199999999999a);
  assert(float_encode(1.1) == 0x3ff199999999999a);

  assert(float_decode(0xbfb999999999999a) == -0.1);
  assert(float_decode(0x3fb999999999999a) == 0.1);
  assert(float_decode(0xbff199999999999a) == -1.1);
  assert(float_decode(0x3ff199999999999a) == 1.1);

  arena_t arena;
  arena_init(&arena);

  assert_equal_integer(&arena, 0, "00");
  assert_equal_integer(&arena, -10, "0c13");
  assert_equal_integer(&arena, -1000, "0dcf07");
  assert_equal_integer(&arena, -100000, "0e3f0d0300");
  assert_equal_integer(&arena, -10000000000, "0fffc717a804000000");
  assert_equal_integer(&arena, -9223372036854775807LL, "0ffdffffffffffffff");
  assert_equal_integer(&arena, 9223372036854775807LL, "0ffeffffffffffffff");
  assert_equal_integer(&arena, -9223372036854775807LL - 1LL,
                       "0fffffffffffffffff");

  assert_equal_double(&arena, -0.1, "1f9a9999999999b9bf");
  assert_equal_double(&arena, 0.1, "1f9a9999999999b93f");
  assert_equal_double(&arena, -1.1, "1f9a9999999999f1bf");
  assert_equal_double(&arena, 1.1, "1f9a9999999999f13f");
  assert_equal_double(&arena, -1.5707963267948966, "1f182d4454fb21f9bf");
  assert_equal_double(&arena, -3.1415926535897930, "1f182d4454fb2109c0");
  assert_equal_double(&arena, -4.7123889803846900, "1fd221337f7cd912c0");
  assert_equal_double(&arena, -6.2831853071795860, "1f182d4454fb2119c0");
  assert_equal_double(&arena, 1.5707963267948966, "1f182d4454fb21f93f");
  assert_equal_double(&arena, 3.1415926535897930, "1f182d4454fb210940");
  assert_equal_double(&arena, 4.7123889803846900, "1fd221337f7cd91240");
  assert_equal_double(&arena, 6.2831853071795860, "1f182d4454fb211940");
  assert_equal_double(&arena, 0.0, "10");
  assert_equal_double(&arena, 1.0, "1f000000000000f03f");
  assert_equal_double(&arena, 1.5, "1f000000000000f83f");
  assert_equal_double(&arena, 2.0, "1f0000000000000040");

  assert_equal_boolean(&arena, false, "20");
  assert_equal_boolean(&arena, true, "21");
  assert_equal_null(&arena, "22");

  assert_equal_bytes(&arena, "", "80");
  assert_equal_bytes(&arena, "00", "8100");
  assert_equal_bytes(&arena, "deadbeef", "84deadbeef");
  assert_equal_bytes(&arena, "74656e742d74797065", "8974656e742d74797065");
  assert_equal_bytes(&arena, "746e2d7965", "85746e2d7965");

  assert_equal_string(&arena, "", "90");
  assert_equal_string(&arena, "Hello", "9548656c6c6f");
  assert_equal_string(&arena, "World", "95576f726c64");
  assert_equal_string(&arena, "🏵ROSETTE", "9bf09f8fb5524f5345545445");
  assert_equal_string(&arena, "🟥🟧🟨🟩🟦🟪", "9c18f09f9fa5f09f9fa7f09f9fa8f09f9fa9f09f9fa6f09f9faa");
  assert_equal_string(&arena, "👶WH", "96f09f91b65748");

  assert_equal_string(&arena, "deadbeef", "a4deadbeef");
  assert_equal_string(&arena, "59d27967b4d859491ed95d8a7eceeaf8d4644ce4",
                      "ac1459d27967b4d859491ed95d8a7eceeaf8d4644ce4");

  arena_deinit(&arena);
}
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

void arena_init(struct arena* arena) {
  arena->start = mmap(NULL, ARENA_SIZE, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  assert(arena->start);
  arena->current = arena->start;
  arena->end = arena->start + ARENA_SIZE;
}

void arena_deinit(struct arena* arena) {
  assert(arena->start);
  munmap(arena->start, ARENA_SIZE);
  arena->start = NULL;
  arena->current = NULL;
}

void* arena_alloc(struct arena* arena, size_t len) {
  assert(arena->current);
  void* ptr = arena->current;
  arena->current += len;
  assert(arena->current < arena->end);
  return ptr;
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

struct nibs_pair {
  uint64_t big;
  unsigned int small : 4;
};

struct nibs_slice {
  const uint8_t* ptr;
  size_t len;
};

enum nibs_node_type {
  NIBS_PAIR,  // The union contains a nibs pair (big/small)
  NIBS_BUF,   // The union contains a slice to be used as-is
  NIBS_HEX,   // The union contains hex string to be used as raw binary
};

union nibs_node_value {
  struct nibs_pair pair;
  struct nibs_slice slice;
};

struct nibs_encode_node {
  enum nibs_node_type type;
  union nibs_node_value value;
  struct nibs_encode_node* next;
};

typedef struct arena arena_t;
typedef struct nibs_pair pair_t;
typedef struct nibs_slice slice_t;
typedef struct nibs_encode_node node_t;

node_t* alloc_pair(arena_t* arena,
                   unsigned int small,
                   uint64_t big,
                   node_t* next) {
  node_t* node = arena_alloc(arena, sizeof(*node));
  node->type = NIBS_PAIR;
  node->value.pair.small = small;
  node->value.pair.big = big;
  node->next = next;
  return node;
}

node_t* alloc_slice(arena_t* arena, const uint8_t* ptr, size_t len) {
  node_t* node = arena_alloc(arena, sizeof(*node));
  node->type = NIBS_BUF;
  node->value.slice.ptr = ptr;
  node->value.slice.len = len;
  node->next = NULL;
  return node;
}

node_t* encode_integer(arena_t* arena, int64_t num) {
  return alloc_pair(arena, NIBS_ZIGZAG, zigzag_encode(num), NULL);
}

node_t* encode_double(arena_t* arena, double num) {
  return alloc_pair(arena, NIBS_FLOAT, float_encode(num), NULL);
}

// Encode a null terminated c-string that's already UTF-8 encoded
node_t* encode_const_string(arena_t* arena, const char* str) {
  size_t len = strlen(str);
  bool hex;
  node_t* body;
  if (len) {
    // Check for even number of lowercase hex inputs.
    hex = (len % 2) == 0;
    if (hex) {
      for (int i = 0; i < len; i++) {
        uint8_t b = str[i];
        if (b < 0x30 || (b > 0x39 && b < 0x61) || b > 0x66) {
          hex = false;
          break;
        }
      }
    }

    body = alloc_slice(arena, (const uint8_t*)str, len);
    if (hex) {
      body->type = NIBS_HEX;
    }
  } else {
    body = NULL;
    hex = false;
  }
  return alloc_pair(arena, hex ? NIBS_HEXSTRING : NIBS_UTF8,
                    hex ? len >> 1 : len, body);
}

static size_t sizeof_node(node_t* node) {
  switch (node->type) {
    case NIBS_PAIR:
      if (node->value.pair.big < 12)
        return 1;
      if (node->value.pair.big < 0x100)
        return 2;
      if (node->value.pair.big < 0x10000)
        return 3;
      if (node->value.pair.big < 0x100000000)
        return 5;
      return 9;
    case NIBS_BUF:
      return node->value.slice.len;
    case NIBS_HEX:
      return node->value.slice.len >> 1;
    default:
      return 0;
  }
}

static int fromhex(uint8_t c) {
  return c < 0x40 ? c - 0x30 : c - 0x61 + 10;
}

void dump_chain(node_t* node) {
  while (node) {
    switch (node->type) {
      case NIBS_PAIR:
        printf("pair(small = %d, big = %lu) ", node->value.pair.small,
               node->value.pair.big);
        break;
      case NIBS_BUF:
        printf("buf(ptr = %p, len = %zu) ", node->value.slice.ptr,
               node->value.slice.len);
        break;
      case NIBS_HEX:
        printf("hex(ptr = %p, len = %zu) ", node->value.slice.ptr,
               node->value.slice.len);
        break;
    }
    node = node->next;
    if (node) {
      printf("-> ");
    }
  }
  printf("\n");
}

slice_t flatten(arena_t* arena, node_t* node) {
  dump_chain(node);
  // Calculate total size needed to encode
  size_t len = 0;
  node_t* current = node;
  while (current) {
    len += sizeof_node(current);
    current = current->next;
  }

  uint8_t* ptr = arena_alloc(arena, len);
  slice_t slice = {.ptr = ptr, .len = len};

  current = node;
  while (current) {
    switch (current->type) {
      case NIBS_PAIR:
        if (current->value.pair.big < 12) {
          *ptr++ = (current->value.pair.small << 4) | current->value.pair.big;
        } else if (current->value.pair.big < 0x100) {
          *ptr++ = (current->value.pair.small << 4) | 12;
          *ptr++ = current->value.pair.big;
        } else if (current->value.pair.big < 0x10000) {
          *ptr++ = (current->value.pair.small << 4) | 13;
          *(uint16_t*)ptr = current->value.pair.big;
          ptr += 2;
        } else if (current->value.pair.big < 0x100000000) {
          *ptr++ = (current->value.pair.small << 4) | 14;
          *(uint32_t*)ptr = current->value.pair.big;
          ptr += 4;
        } else {
          *ptr++ = (current->value.pair.small << 4) | 15;
          *(uint64_t*)ptr = current->value.pair.big;
          ptr += 8;
        }
        break;
      case NIBS_BUF:
        memcpy(ptr, current->value.slice.ptr, current->value.slice.len);
        ptr += current->value.slice.len;
        break;
      case NIBS_HEX:
        for (int i = 0; i < current->value.slice.len; i += 2) {
          *ptr++ = (fromhex(current->value.slice.ptr[i]) << 4) |
                   (fromhex(current->value.slice.ptr[i + 1]));
        }
        break;
    }
    len += sizeof_node(current);
    current = current->next;
  }

  return slice;
}

bool slice_equal(slice_t actual, slice_t expected) {
  printf("expected: ");
  for (int i = 0; i < expected.len; i++) {
    printf("%02x", expected.ptr[i]);
  }
  printf("\nactual:   ");
  for (int i = 0; i < actual.len; i++) {
    if (i < expected.len && actual.ptr[i] != expected.ptr[i]) {
      printf("\033[31m%02x\033[0m", actual.ptr[i]);
    } else {
      printf("%02x", actual.ptr[i]);
    }
  }
  printf("\n");

  if (expected.len != actual.len) {
    printf("Expected length %ld, but got %ld\n", expected.len, actual.len);
    return false;
  }
  for (int i = 0; i < actual.len; i++) {
    if (expected.ptr[i] != actual.ptr[i])
      return false;
  }
  return true;
}

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

  assert(slice_equal(flatten(&arena, encode_integer(&arena, 0)),
                     (slice_t){.ptr = (const uint8_t*)"\x00", .len = 1}));
  assert(slice_equal(flatten(&arena, encode_integer(&arena, -10)),
                     (slice_t){.ptr = (const uint8_t*)"\x0c\x13", .len = 2}));
  assert(
      slice_equal(flatten(&arena, encode_integer(&arena, -1000)),
                  (slice_t){.ptr = (const uint8_t*)"\x0d\xcf\x07", .len = 3}));
  assert(slice_equal(
      flatten(&arena, encode_integer(&arena, -100000)),
      (slice_t){.ptr = (const uint8_t*)"\x0e\x3f\x0d\x03\x00", .len = 5}));
  assert(slice_equal(
      flatten(&arena, encode_integer(&arena, -10000000000)),
      (slice_t){.ptr = (const uint8_t*)"\x0f\xff\xc7\x17\xa8\x04\x00\x00\x00",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_integer(&arena, -9223372036854775807LL)),
      (slice_t){.ptr = (const uint8_t*)"\x0f\xfd\xff\xff\xff\xff\xff\xff\xff",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_integer(&arena, 9223372036854775807LL)),
      (slice_t){.ptr = (const uint8_t*)"\x0f\xfe\xff\xff\xff\xff\xff\xff\xff",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_integer(&arena, -9223372036854775807LL - 1LL)),
      (slice_t){.ptr = (const uint8_t*)"\x0f\xff\xff\xff\xff\xff\xff\xff\xff",
                .len = 9}));

  assert(slice_equal(
      flatten(&arena, encode_double(&arena, -1.5707963267948966)),
      (slice_t){.ptr = (const uint8_t*)"\x1f\x18\x2d\x44\x54\xfb\x21\xf9\xbf",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_double(&arena, -3.1415926535897930)),
      (slice_t){.ptr = (const uint8_t*)"\x1f\x18\x2d\x44\x54\xfb\x21\x09\xc0",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_double(&arena, -4.7123889803846900)),
      (slice_t){.ptr = (const uint8_t*)"\x1f\xd2\x21\x33\x7f\x7c\xd9\x12\xc0",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_double(&arena, -6.2831853071795860)),
      (slice_t){.ptr = (const uint8_t*)"\x1f\x18\x2d\x44\x54\xfb\x21\x19\xc0",
                .len = 9}));
  assert(slice_equal(flatten(&arena, encode_double(&arena, 0.0)),
                     (slice_t){.ptr = (const uint8_t*)"\x10", .len = 1}));
  assert(slice_equal(
      flatten(&arena, encode_double(&arena, 1.5707963267948966)),
      (slice_t){.ptr = (const uint8_t*)"\x1f\x18\x2d\x44\x54\xfb\x21\xf9\x3f",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_double(&arena, 3.1415926535897930)),
      (slice_t){.ptr = (const uint8_t*)"\x1f\x18\x2d\x44\x54\xfb\x21\x09\x40",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_double(&arena, 4.7123889803846900)),
      (slice_t){.ptr = (const uint8_t*)"\x1f\xd2\x21\x33\x7f\x7c\xd9\x12\x40",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_double(&arena, 6.2831853071795860)),
      (slice_t){.ptr = (const uint8_t*)"\x1f\x18\x2d\x44\x54\xfb\x21\x19\x40",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_double(&arena, 1.0)),
      (slice_t){.ptr = (const uint8_t*)"\x1f\x00\x00\x00\x00\x00\x00\xf0\x3f",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_double(&arena, 1.5)),
      (slice_t){.ptr = (const uint8_t*)"\x1f\x00\x00\x00\x00\x00\x00\xf8\x3f",
                .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_double(&arena, 2.0)),
      (slice_t){.ptr = (const uint8_t*)"\x1f\x00\x00\x00\x00\x00\x00\x00\x40",
                .len = 9}));

  assert(slice_equal(flatten(&arena, encode_boolean(&arena, false)),
                     (slice_t){.ptr = (const uint8_t*)"\x20", .len = 1}));
  assert(slice_equal(flatten(&arena, encode_boolean(&arena, true)),
                     (slice_t){.ptr = (const uint8_t*)"\x21", .len = 1}));
  assert(slice_equal(flatten(&arena, encode_null(&arena)),
                     (slice_t){.ptr = (const uint8_t*)"\x22", .len = 1}));

  assert(slice_equal(flatten(&arena, encode_const_string(&arena, "")),
                     (slice_t){.ptr = (const uint8_t*)"\x90", .len = 1}));
  assert(slice_equal(
      flatten(&arena, encode_const_string(&arena, "Hello")),
      (slice_t){.ptr = (const uint8_t*)"\x95\x48\x65\x6c\x6c\x6f", .len = 6}));
  assert(slice_equal(
      flatten(&arena, encode_const_string(&arena, "World")),
      (slice_t){.ptr = (const uint8_t*)"\x95\x57\x6f\x72\x6c\x64", .len = 6}));
  assert(
      slice_equal(flatten(&arena, encode_const_string(&arena, "🏵ROSETTE")),
                  (slice_t){.ptr = (const uint8_t*)"\x9b\xf0\x9f\x8f\xb5\x52"
                                                   "\x4f\x53\x45\x54\x54\x45",
                            .len = 12}));
  assert(slice_equal(
      flatten(&arena, encode_const_string(&arena, "🟥🟧🟨🟩🟦🟪")),
      (slice_t){.ptr = (const uint8_t*)"\x9c\x18\xf0\x9f\x9f\xa5\xf0\x9f\x9f"
                                       "\xa7\xf0\x9f\x9f"
                                       "\xa8\xf0\x9f\x9f\xa9\xf0\x9f\x9f\xa6"
                                       "\xf0\x9f\x9f\xaa",
                .len = 26}));
  assert(slice_equal(
      flatten(&arena, encode_const_string(&arena, "👶WH")),
      (slice_t){.ptr = (const uint8_t*)"\x96\xf0\x9f\x91\xb6\x57\x48",
                .len = 7}));
  assert(slice_equal(
      flatten(&arena, encode_const_string(&arena, "deadbeef")),
      (slice_t){.ptr = (const uint8_t*)"\xa4\xde\xad\xbe\xef", .len = 5}));
  assert(slice_equal(
      flatten(&arena, encode_const_string(
                          &arena, "59d27967b4d859491ed95d8a7eceeaf8d4644ce4")),
      (slice_t){
          .ptr = (const uint8_t*)"\xac\x14\x59\xd2\x79\x67\xb4\xd8\x59\x49\x1e"
                                 "\xd9\x5d\x8a\x7e\xce\xea\xf8\xd4\x64\x4c\xe4",
          .len = 22}));
  arena_deinit(&arena);
}
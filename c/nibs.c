#define _GNU_SOURCE
#include <assert.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>

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
  return alloc_pair(arena, NIBS_ZIGZAG, float_encode(num), NULL);
}

// Encode a null terminated c-string that's already UTF-8 encoded
node_t* encode_const_string(arena_t* arena, const char* str) {
  size_t len = strlen(str);
  node_t* body = alloc_slice(arena, str, len);
  // Check for even number of lowercase hex inputs.
  bool hex = (len % 2) == 0;
  if (hex) {
    for (int i = 0; i < len; i++) {
      uint8_t b = str[i];
      if (b < 0x30 || (b > 0x39 && b < 0x61) || b > 0x66) {
        hex = false;
        break;
      }
    }
  }
  if (hex) {
    body->type = NIBS_HEX;
  }
  return alloc_pair(arena, hex ? NIBS_HEXSTRING : NIBS_UTF8, len, body);
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

slice_t flatten(arena_t* arena, node_t* node) {
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
      case NIBS_BUF:
        memcpy(ptr, current->value.slice.ptr, current->value.slice.len);
        ptr += current->value.slice.len;
        break;
      case NIBS_HEX:
        assert(false);  // TODO: hex encode
        ptr += current->value.slice.len >> 1;
        break;
    }
    len += sizeof_node(current);
    current = current->next;
  }

  return slice;
}

#include <stdio.h>

bool slice_equal(slice_t actual, slice_t expected) {
  if (expected.len != actual.len) {
    printf("Expected length %ld, but got %d\n", expected.len, actual.len);
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
                     (slice_t){.ptr = "\x00", .len = 1}));
  assert(slice_equal(flatten(&arena, encode_integer(&arena, -10)),
                     (slice_t){.ptr = "\x0c\x13", .len = 2}));
  assert(slice_equal(flatten(&arena, encode_integer(&arena, -1000)),
                     (slice_t){.ptr = "\x0d\xcf\x07", .len = 3}));
  assert(slice_equal(flatten(&arena, encode_integer(&arena, -100000)),
                     (slice_t){.ptr = "\x0e\x3f\x0d\x03\x00", .len = 5}));
  assert(slice_equal(
      flatten(&arena, encode_integer(&arena, -10000000000)),
      (slice_t){.ptr = "\x0f\xff\xc7\x17\xa8\x04\x00\x00\x00", .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_integer(&arena, -9223372036854775807)),
      (slice_t){.ptr = "\x0f\xfd\xff\xff\xff\xff\xff\xff\xff", .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_integer(&arena, 9223372036854775807)),
      (slice_t){.ptr = "\x0f\xfe\xff\xff\xff\xff\xff\xff\xff", .len = 9}));
  assert(slice_equal(
      flatten(&arena, encode_integer(&arena, -9223372036854775808)),
      (slice_t){.ptr = "\x0f\xff\xff\xff\xff\xff\xff\xff\xff", .len = 9}));

  // assert(slice_equal(flatten(&arena, encode_double(&arena,
  // -1.5707963267948966)),
  //                    (slice_t){.ptr = "\x1f\x18\x2d\x44\x54\xfb\x21\xf9\xbf",
  //                    .len = 9}));

  assert(slice_equal(flatten(&arena, encode_const_string(&arena, "")),
                     (slice_t){.ptr = "\x90", .len = 1}));
  assert(slice_equal(flatten(&arena, encode_const_string(&arena, "Hello")),
                     (slice_t){.ptr = "\x95\x48\x65\x6c\x6c\x6f", .len = 6}));
  assert(slice_equal(flatten(&arena, encode_const_string(&arena, "World")),
                     (slice_t){.ptr = "\x95\x57\x6f\x72\x6c\x6f", .len = 6}));
  assert(slice_equal(
      flatten(&arena, encode_const_string(&arena, "🏵ROSETTE")),
      (slice_t){.ptr = "\x9b\xf0\x9f\x8f\xb5\x52\x4f\x53\x45\x54\x54\x45",
                .len = 12}));
  assert(slice_equal(
      flatten(&arena, encode_const_string(&arena, "🟥🟧🟨🟩🟦🟪")),
      (slice_t){.ptr = "\x9c\x18\xf0\x9f\x9f\xa5\xf0\x9f\x9f\xa7\xf0\x9f\x9f"
                       "\xa8\xf0\x9f\x9f\xa9\xf0\x9f\x9f\xa6\xf0\x9f\x9f\xaa",
                .len = 26}));
  assert(
      slice_equal(flatten(&arena, encode_const_string(&arena, "👶WH")),
                  (slice_t){.ptr = "\x96\xf0\x9f\x91\xb6\x57\x48", .len = 7}));
  assert(slice_equal(flatten(&arena, encode_const_string(&arena, "deadbeef")),
                     (slice_t){.ptr = "\xa4\xde\xad\xbe\xef", .len = 5}));

  // -1.5707963267948966, <1f182d4454fb21f9bf>,
  // -3.1415926535897930, <1f182d4454fb2109c0>,
  // -4.7123889803846900, <1fd221337f7cd912c0>,
  // -6.2831853071795860, <1f182d4454fb2119c0>,
  //  1.5707963267948966, <1f182d4454fb21f93f>,
  //  3.1415926535897930, <1f182d4454fb210940>,
  //  4.7123889803846900, <1fd221337f7cd91240>,
  //  6.2831853071795860, <1f182d4454fb211940>,

  arena_deinit(&arena);
}
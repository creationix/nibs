#include "nibs.h"
#define _GNU_SOURCE
#include <assert.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

static node_t* hex_str(arena_t* arena, const char* str) {
  size_t len = strlen(str);
  assert(len % 2 == 0);
  len >>= 1;
  node_t* buf = alloc_slice(arena, len, NULL);
  hexcpy(buf->data, (const uint8_t*)str, len);
  return buf;
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

#define assert_equal_bytes(arena, actual, expected)                \
  assert(slice_equal(arena, encode_hex_bytes(arena, actual, NULL), \
                     hex_str(arena, expected)))

static void assert_equal_node(arena_t* arena,
                              node_t* node,
                              const char* expected) {
  assert(slice_equal(arena, node, hex_str(arena, expected)));
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
  assert_equal_string(&arena, "🟥🟧🟨🟩🟦🟪",
                      "9c18f09f9fa5f09f9fa7f09f9fa8f09f9fa9f09f9fa6f09f9faa");
  assert_equal_string(&arena, "👶WH", "96f09f91b65748");

  assert_equal_string(&arena, "deadbeef", "a4deadbeef");
  assert_equal_string(&arena, "59d27967b4d859491ed95d8a7eceeaf8d4644ce4",
                      "ac1459d27967b4d859491ed95d8a7eceeaf8d4644ce4");

  assert_equal_node(&arena, encode_list(&arena, 3, (node_t*[]){}, NULL), "b0");

  assert_equal_node(&arena,
                    encode_list(&arena, 3,
                                (node_t*[]){
                                    encode_integer(&arena, 1, NULL),
                                    encode_integer(&arena, 2, NULL),
                                    encode_integer(&arena, 3, NULL),
                                },
                                NULL),
                    "b3020406");

  assert_equal_node(
      &arena,
      encode_list(
          &arena, 3,
          (node_t*[]){
              encode_list(&arena, 1,
                          (node_t*[]){encode_integer(&arena, 1, NULL)}, NULL),
              encode_list(&arena, 1,
                          (node_t*[]){encode_integer(&arena, 2, NULL)}, NULL),
              encode_list(&arena, 1,
                          (node_t*[]){encode_integer(&arena, 3, NULL)}, NULL),
          },
          NULL),
      "b6b102b104b106");

  arena_deinit(&arena);
}
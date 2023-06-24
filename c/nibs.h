#ifndef NIBS_H
#define NIBS_H

#include <stdbool.h>
#include <stdint.h>
#include "arena.h"
#include "slice.h"

enum nibs_types {
  NIBS_ZIGZAG = 0,
  NIBS_FLOAT = 1,
  NIBS_SIMPLE = 2,
  NIBS_REF = 3,
  NIBS_BYTES = 8,
  NIBS_UTF8 = 9,
  NIBS_HEXSTRING = 10,
  NIBS_LIST = 11,
  NIBS_MAP = 12,
  NIBS_ARRAY = 13,
  NIBS_TRIE = 14,
  NIBS_SCOPE = 15,
};

enum nibs_subtypes {
  NIBS_FALSE = 0,
  NIBS_TRUE = 1,
  NIBS_NULL = 2,
};

slice_node_t* nibs_alloc_pair(arena_t* arena,
                              unsigned int small,
                              uint64_t big,
                              bool is_container);
slice_node_t* nibs_encode_integer(arena_t* arena, int64_t num);
slice_node_t* nibs_encode_double(arena_t* arena, double num);
slice_node_t* nibs_encode_boolean(arena_t* arena, bool val);
slice_node_t* nibs_encode_null(arena_t* arena);
// slice_node_t* nibs_encode_string(arena_t* arena, const char* str, int len);

#endif

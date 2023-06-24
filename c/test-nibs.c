#include "arena.c"
#include "nibs.c"
#include "slice.h"
#include "tibs.c"
#define _GNU_SOURCE
#include <assert.h>
#include <fcntl.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static slice_node_t* nibs_parse_list(arena_t* arena, const char* tibs, int* offset, int len, int indexed);
// static int parse_map(const char* tibs, int offset, int len, int indexed);
// static int parse_scope(const char* tibs, int offset, int len);

static int is_hex(char c) {
  return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
}

static int from_hex(char c) {
  return c < 'a' ? c - '0' : c - 'a' + 10;
}

static slice_node_t* nibs_process_token(arena_t* arena, const char* tibs, int len, int* offset, struct tibs_token token) {
  switch (token.type) {
    case TIBS_NULL:
      *offset = token.offset + token.len;
      return nibs_encode_null(arena);
    case TIBS_BOOLEAN:
      *offset = token.offset + token.len;
      return nibs_encode_boolean(arena, tibs[token.offset] == 't');
    case TIBS_NUMBER: {
      double num = strtod(tibs + token.offset, NULL);
      // TODO: encode integers
      // TODO: encode nil/inf
      *offset = token.offset + token.len;
      return nibs_encode_double(arena, num);
    }
    case TIBS_BYTES: {
      int i = token.offset + 1;
      int e = token.offset + token.len - 1;
      int count = 0;
      while (i < e) {
        while (!is_hex(tibs[i]))
          i++;
        i++;
        while (!is_hex(tibs[i]))
          i++;
        i++;
        count++;
      }
      slice_node_t* node = nibs_alloc_pair(arena, NIBS_BYTES, count, true);
      size_t o = node->len - count;
      count = 0;
      i = token.offset + 1;
      while (i < e) {
        while (!is_hex(tibs[i]))
          i++;
        int high = from_hex(tibs[i++]);
        while (!is_hex(tibs[i]))
          i++;
        int low = from_hex(tibs[i++]);
        node->data[o + count++] = (high << 4) | low;
      }
      *offset = token.offset + token.len;
      return node;
    }
    case TIBS_STRING:
      // TODO: process escapes
      // TODO: use hexstring when possible
      int count = token.len - 2; // Assume just quotes are removed
      slice_node_t* node = nibs_alloc_pair(arena, NIBS_BYTES, count, true);
      size_t o = node->len - count;
      memcpy(node->data + o, tibs + token.offset + 1, count);
      *offset = token.offset + token.len;
      return node;
    case TIBS_REF: {
      long num = atol(tibs + token.offset + 1);
      *offset = token.offset + token.len;
      return nibs_alloc_pair(arena, NIBS_REF, num, false);
    }
    case TIBS_LIST_BEGIN: {
    case TIBS_MAP_BEGIN:
    case TIBS_SCOPE_BEGIN:
      *offset = token.offset + token.len;
      return nibs_parse_list(arena, tibs, offset, len, token.len > 1);
    }
      // return parse_map(tibs, token.offset + token.len, len, token.len > 1);
      // return parse_scope(tibs, token.offset + token.len, len);
    case TIBS_EOS:
    case TIBS_LIST_END:
    case TIBS_MAP_END:
    case TIBS_SCOPE_END:
      break;
  }
  return NULL;
}

static slice_node_t* nibs_parse_list(arena_t* arena, const char* tibs, int* offset, int len, int indexed) {
  if (indexed) {
    // TODO: generate index
  }
  int total_bytes = 0;
  slice_node_t* tail = NULL;
  slice_node_t* head = NULL;
  while (1) {
    struct tibs_token token = tibs_parse(tibs, *offset, len);
    if (token.type == TIBS_EOS || token.type == TIBS_LIST_END || token.type == TIBS_SCOPE_END || token.type == TIBS_MAP_END) {
      *offset = token.offset + token.len;
      break;
    }
    slice_node_t* child = nibs_process_token(arena, tibs, len, offset, token);
    total_bytes += child->len;
    if (!head) {
      head = child;
    } else {
      tail->next = child;
    }
    tail = child;
  }
  slice_node_t* node = nibs_alloc_pair(arena, NIBS_LIST, total_bytes, false);
  node->next = head;
  return node;
}

int main(int argc, char** argv) {
  arena_t arena;
  arena_init(&arena);

  // Open the file
  const char* filename = argc > 1 ? argv[1] : "../fixtures/tibs-fixtures.txt";
  int fd = open(filename, O_RDONLY);
  assert(fd);

  // Get it's size
  struct stat filestat;
  int status = fstat(fd, &filestat);
  assert(!status);

  // Map the file
  char* data = mmap(NULL, filestat.st_size, PROT_READ, MAP_SHARED, fd, 0);
  assert(data != MAP_FAILED);

  // Parse the mapped file
  int offset = 0;
  while (1) {
    struct tibs_token token = tibs_parse(data, offset, filestat.st_size);
    if (token.type == TIBS_EOS) {
      break;
    }
    slice_node_t* node = nibs_process_token(&arena, data, filestat.st_size, &offset, token);

    // Dump chain to stdout
    while (node) {
      fprintf(stderr, "<");
      for (int i = 0; i < node->len; i++) {
        fprintf(stderr, "%02x", node->data[i]);
      }
      fprintf(stderr, ">");
      printf("%.*s", node->len, node->data);
      node = node->next;
    }
    fprintf(stderr, "\n");
  }

  // Let it go
  munmap(data, filestat.st_size);
  close(fd);

  arena_deinit(&arena);
}

// static int fromhex(uint8_t c) {
//   return c < 'a' ? c - '0' : c - 'a' + 10;
// }

// static void hexcpy(uint8_t* dest, const uint8_t* source, int len) {
//   for (int i = 0; i < len; i++) {
//     dest[i] = (fromhex(source[i * 2]) << 4) | fromhex(source[i * 2 + 1]);
//   }
// }

// // Encode a null terminated c-string that's already UTF-8 encoded
// slice_node_t* encode_string(arena_t* arena,
//                             const char* str,
//                             slice_node_t* next) {
//   size_t len = strlen(str);
//   slice_node_t* body;
//   if (len) {
//     if (is_hex(str, len)) {
//       len >>= 1;
//       body = alloc_slice(arena, len, next);
//       hexcpy(body->data, (uint8_t*)str, len);
//       return alloc_pair(arena, NIBS_HEXSTRING, len, body);
//     }
//     body = alloc_slice(arena, len, next);
//     memcpy(body->data, str, len);
//     return alloc_pair(arena, NIBS_UTF8, len, body);
//   }
//   return alloc_pair(arena, NIBS_UTF8, 0, next);
// }

// // Encode a null terminated c-string that's already UTF-8 encoded
// slice_node_t* encode_hex_bytes(arena_t* arena,
//                                const char* str,
//                                slice_node_t* next) {
//   size_t len = strlen(str);
//   assert(len % 2 == 0);
//   len >>= 1;
//   slice_node_t* body = alloc_slice(arena, len, next);
//   hexcpy(body->data, (uint8_t*)str, len);
//   return alloc_pair(arena, NIBS_BYTES, len, body);
// }

// void dump_chain(slice_node_t* node) {
//   while (node) {
//     printf("(ptr = %p, len = %zu) ", node->data, node->len);
//     node = node->next;
//     if (node) {
//       printf("-> ");
//     }
//   }
//   printf("\n");
// }

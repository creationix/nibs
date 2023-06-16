#include "tibs.h"
#include "nibs.h"
#define _GNU_SOURCE
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

int parse_list(const char* tibs, int offset, int len, int indexed);
int parse_map(const char* tibs, int offset, int len, int indexed);
int parse_scope(const char* tibs, int offset, int len);

int process_token(const char* tibs,
                  int len,
                  struct tibs_token token) {
  switch (token.type) {
    case TIBS_NULL:
      printf("null");
      return token.offset + token.len;
    case TIBS_BOOLEAN:
      printf("%.*s", token.len, tibs + token.offset);
      return token.offset + token.len;
    case TIBS_NUMBER:
      printf("%.*s", token.len, tibs + token.offset);
      return token.offset + token.len;
    case TIBS_BYTES: {
      int i = token.offset + 1;
      printf("<");
      while (i < token.offset + token.len - 1) {
        while (tibs[i] < '0' || (tibs[i] > '9' && tibs[i] < 'a') || tibs[i] > 'f') {
          i++;
        }
        int high = tibs[i] < 'a' ? tibs[i] - '0' : tibs[i] - 'a' + 10;
        i++;
        while (tibs[i] < '0' || (tibs[i] > '9' && tibs[i] < 'a') || tibs[i] > 'f') {
          i++;
        }
        int low = tibs[i] < 'a' ? tibs[i] - '0' : tibs[i] - 'a' + 10;
        i++;
        printf("%02x", high << 4 | low);
      }
      printf(">");
      return token.offset + token.len;
    }
    case TIBS_STRING:
      printf("%.*s", token.len, tibs + token.offset);
      return token.offset + token.len;
    case TIBS_REF:
      printf("%.*s", token.len, tibs + token.offset);
      return token.offset + token.len;
    case TIBS_LIST_BEGIN:
      return parse_list(tibs, token.offset + token.len, len, token.len > 1);
    case TIBS_MAP_BEGIN:
      return parse_map(tibs, token.offset + token.len, len, token.len > 1);
    case TIBS_SCOPE_BEGIN:
      return parse_scope(tibs, token.offset + token.len, len);
    case TIBS_EOS:
    case TIBS_LIST_END:
    case TIBS_MAP_END:
    case TIBS_SCOPE_END:
      break;
  }
  printf("**%.*s**", token.len, tibs + token.offset);
  assert(token.len);
  return token.offset + token.len;
}

int parse_list(const char* tibs, int offset, int len, int indexed) {
  if (indexed) {
    printf("[#");
  } else {
    printf("[");
  }
  for (int i = 0; 1; i++) {
    struct tibs_token token = tibs_parse(tibs, offset, len);
    if (token.type == TIBS_LIST_END) {
      printf("]");
      return token.offset + token.len;
    }
    if (i > 0) {
      printf(",");
    }
    offset = process_token(tibs, len, token);
  }
}

int parse_map(const char* tibs, int offset, int len, int indexed) {
  if (indexed) {
    printf("{#");
  } else {
    printf("{");
  }
  for (int i = 0; 1; i++) {
    struct tibs_token token = tibs_parse(tibs, offset, len);
    if (token.type == TIBS_MAP_END) {
      printf("}");
      return token.offset + token.len;
    }
    if (i > 0) {
      if (i % 2) {
        printf(":");
      } else {
        printf(",");
      }
    }
    offset = process_token(tibs, len, token);
  }
}

int parse_scope(const char* tibs, int offset, int len) {
  printf("(");
  for (int i = 0; 1; i++) {
    struct tibs_token token = tibs_parse(tibs, offset, len);
    if (token.type == TIBS_SCOPE_END) {
      printf(")");
      return token.offset + token.len;
    }
    if (i > 0) {
      printf(",");
    }
    offset = process_token(tibs, len, token);
  }
}

int main(int argc, const char** argv) {
  // Open the file
  assert(argc > 1);
  const char* filename = argv[1];
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
  for (int i = 0; 1; i++) {
    struct tibs_token token = tibs_parse(data, offset, filestat.st_size);
    if (token.type == TIBS_EOS) {
      break;
    }
    offset = process_token(data, filestat.st_size, token);
    printf("\n");
  }

  // Let it go
  munmap(data, filestat.st_size);
  close(fd);
}
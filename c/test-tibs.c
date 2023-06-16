#include "tibs.h"
#define _GNU_SOURCE
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static const char* tibs_type_names[] = {
    "null",        "boolean",   "number",  "bytes",      "string",
    "ref",         "map_begin", "map_end", "list_begin", "list_end",
    "scope_begin", "scope_end", "eos"};

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
  while (1) {
    struct tibs_token token = tibs_parse(data, offset, filestat.st_size);
    if (token.type == TIBS_EOS)
      break;
    printf("  %s %.*s\n", tibs_type_names[token.type], token.len,
           data + token.offset);
    offset = token.offset + token.len;
  }

  // Let it go
  munmap(data, filestat.st_size);
  close(fd);
}
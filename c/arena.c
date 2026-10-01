#include "arena.h"
#define _GNU_SOURCE
#include <sys/mman.h>
#include <assert.h>

void arena_init(arena_t* arena) {
  arena->start = mmap(0, ARENA_SIZE, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  assert(arena->start);
  arena->current = arena->start;
  arena->end = arena->start + ARENA_SIZE;
}

void arena_deinit(arena_t* arena) {
  assert(arena->start);
  munmap(arena->start, ARENA_SIZE);
  arena->start = 0;
  arena->current = 0;
}

void* arena_alloc(arena_t* arena, int len) {
  assert(arena->current);
  void* ptr = arena->current;
  arena->current += len;
  assert(arena->current < arena->end);
  return ptr;
}

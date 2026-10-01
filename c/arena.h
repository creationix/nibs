#ifndef ARENA_H
#define ARENA_H

#ifndef ARENA_SIZE
#define ARENA_SIZE 0x40000000  // 1 GiB
#endif

struct arena {
  void* start;
  void* current;
  void* end;
};
typedef struct arena arena_t;

void arena_init(arena_t* arena);
void arena_deinit(arena_t* arena);
void* arena_alloc(arena_t* arena, int len);

#endif // ARENA_H
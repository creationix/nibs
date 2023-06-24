#ifndef SLICE_H
#define SLICE_H

struct slice_node {
  struct slice_node* next;
  int len;
  unsigned char data[];
};
typedef struct slice_node slice_node_t;

#endif // SLICE_H
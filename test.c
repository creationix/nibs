
#include <stdint.h>

uint64_t encodeZigZag(int64_t i) {
  return (i >> 63) ^ (i << 1);
}
int64_t decodeZigZag(uint64_t i) {
  return (i >> 1) ^ -(i & 1);
}
// Convert between signed value and unsigned bit representations.
uint64_t encodeDouble(double i) {
  return *(uint64_t*)(&i);
}
double decodeDouble(uint64_t i) {
  return *(double*)(&i);
}
// Convert between signed value and unsigned bit representations.
uint32_t encodeFloat(float i) {
  return *(uint32_t*)(&i);
}
float decodeFloat(uint32_t i) {
  return *(float*)(&i);
}

#include <stdio.h>

void dumpDouble(double d) {
  float f = (float)d;
  if ((double)f == d) {
    printf("        %08x %f\n", encodeFloat(f), d);
  } else {
    printf("%016llx %f\n", encodeDouble(d), d);
    printf("%016llx %f *\n", encodeDouble(f), f);
  }
}

int main() {
  printf("%016llx\n", encodeZigZag(0));
  printf("%016llx\n", encodeZigZag(1));
  printf("%016llx\n", encodeZigZag(2));
  printf("%016llx\n", encodeZigZag(3));
  printf("%016llx\n", encodeZigZag(4));
  printf("%016llx\n", encodeZigZag(-1));
  printf("%016llx\n", encodeZigZag(-2));
  printf("%016llx\n", encodeZigZag(-3));
  printf("%016llx\n", encodeZigZag(-4));
  for (int i = 0; i < 100; i++) {
    dumpDouble(i);
    dumpDouble(-i);
    dumpDouble(((double)i) / 10);
    dumpDouble(((double)i) / -10);
    dumpDouble(((double)i) / 100);
    dumpDouble(((double)i) / -100);
  }
}
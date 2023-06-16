#include "tibs.h"

// Check if one null terminated string begins with another
static int starts_with(const char* prefix,
                       const char* tibs,
                       int offset,
                       int len) {
  for (; offset < len; offset++) {
    if (*prefix == 0) {
      return 1;
    }
    if (*prefix != tibs[offset]) {
      return 0;
    }
  }
  return 0;
}

// Parse a single token from the given tibs string and offset.
struct tibs_token tibs_parse(const char* tibs, int offset, int len) {
  for (; offset < len; offset++) {
    if (starts_with("null", tibs, offset, len)) {
      return (struct tibs_token){TIBS_NULL, offset, 4};
    }
    if (starts_with("true", tibs, offset, len)) {
      return (struct tibs_token){TIBS_BOOLEAN, offset, 4};
    }
    if (starts_with("false", tibs, offset, len)) {
      return (struct tibs_token){TIBS_BOOLEAN, offset, 5};
    }
    if (starts_with("-inf", tibs, offset, len)) {
      return (struct tibs_token){TIBS_NUMBER, offset, 4};
    }
    if (starts_with("inf", tibs, offset, len)) {
      return (struct tibs_token){TIBS_NUMBER, offset, 3};
    }
    if (starts_with("nan", tibs, offset, len)) {
      return (struct tibs_token){TIBS_NUMBER, offset, 3};
    }
    if (tibs[offset] == '-' || (tibs[offset] >= '0' && tibs[offset] <= '9')) {
      int len = 1;
      while (tibs[offset + len] >= '0' && tibs[offset + len] <= '9') {
        len++;
      }
      if (tibs[offset + len] == '.') {
        len++;
        while (tibs[offset + len] >= '0' && tibs[offset + len] <= '9') {
          len++;
        }
      }
      if (tibs[offset + len] == 'e' || tibs[offset + len] == 'E') {
        len++;
        if (tibs[offset + len] == '-' || tibs[offset + len] == '+') {
          len++;
        }
        while (tibs[offset + len] >= '0' && tibs[offset + len] <= '9') {
          len++;
        }
      }
      return (struct tibs_token){TIBS_NUMBER, offset, len};
    }
    if (tibs[offset] == '"') {
      int len = 1;
      while (tibs[offset + len] != '"') {
        if (tibs[offset + len] == '\\') {
          len++;
        }
        len++;
      }
      return (struct tibs_token){TIBS_STRING, offset, len + 1};
    }
    if (tibs[offset] == '<') {
      int len = 1;
      while (tibs[offset + len] != '>') {
        len++;
      }
      return (struct tibs_token){TIBS_BYTES, offset, len + 1};
    }
    if (tibs[offset] == '&') {
      int len = 1;
      while (tibs[offset + len] >= '0' && tibs[offset + len] <= '9') {
        len++;
      }
      return (struct tibs_token){TIBS_REF, offset, len};
    }
    if (tibs[offset] == '[') {
      int len = tibs[offset + 1] == '#' ? 2 : 1;
      return (struct tibs_token){TIBS_LIST_BEGIN, offset, len};
    }
    if (tibs[offset] == ']') {
      return (struct tibs_token){TIBS_LIST_END, offset, 1};
    }
    if (tibs[offset] == '{') {
      int len = tibs[offset + 1] == '#' ? 2 : 1;
      return (struct tibs_token){TIBS_MAP_BEGIN, offset, len};
    }
    if (tibs[offset] == '}') {
      return (struct tibs_token){TIBS_MAP_END, offset, 1};
    }
    if (tibs[offset] == '(') {
      return (struct tibs_token){TIBS_SCOPE_BEGIN, offset, 1};
    }
    if (tibs[offset] == ')') {
      return (struct tibs_token){TIBS_SCOPE_END, offset, 1};
    }
  }
  return (struct tibs_token){.type = TIBS_EOS, .offset = offset, .len = 0};
}

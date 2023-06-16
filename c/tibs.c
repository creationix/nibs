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
    char c = tibs[offset];
    // Fast skip common whitespace and separators
    if (c == ' ' || c == '\t' || c == '\r' ||
        c == '\n' || c == ',' || c == ':') {
      continue;
    }
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
    if (c == '-' || (c >= '0' && c <= '9')) {
      int i = offset + 1;
      while (i < len && tibs[i] >= '0' && tibs[i] <= '9') {
        i++;
      }
      if (i < len && tibs[i] == '.') {
        i++;
        while (i < len && tibs[i] >= '0' && tibs[i] <= '9') {
          i++;
        }
      }
      if (i < len && tibs[i] == 'e' || tibs[i] == 'E') {
        i++;
        if (i < len && tibs[i] == '-' || tibs[i] == '+') {
          i++;
        }
        while (i < len && tibs[i] >= '0' && tibs[i] <= '9') {
          i++;
        }
      }
      return (struct tibs_token){TIBS_NUMBER, offset, i - offset};
    }
    if (c == '"') {
      int i = offset + 1;
      while (i < len && tibs[i] != '"') {
        if (tibs[i] == '\\') {
          i++;
        }
        i++;
      }
      return (struct tibs_token){TIBS_STRING, offset, i - offset + 1};
    }
    if (c == '[') {
      return (struct tibs_token){TIBS_LIST_BEGIN, offset, tibs[offset + 1] == '#' ? 2 : 1};
    }
    if (c == ']') {
      return (struct tibs_token){TIBS_LIST_END, offset, 1};
    }
    if (c == '{') {
      return (struct tibs_token){TIBS_MAP_BEGIN, offset, tibs[offset + 1] == '#' ? 2 : 1};
    }
    if (c == '}') {
      return (struct tibs_token){TIBS_MAP_END, offset, 1};
    }
    if (c == '<') {
      int i = offset + 1;
      while (i < len && tibs[i] != '>') {
        i++;
      }
      return (struct tibs_token){TIBS_BYTES, offset, i - offset + 1};
    }
    if (c == '&') {
      int i = offset + 1;
      while (i < len && tibs[i] >= '0' && tibs[offset + i] <= '9') {
        i++;
      }
      return (struct tibs_token){TIBS_REF, offset, i - offset};
    }
    if (c == '(') {
      return (struct tibs_token){TIBS_SCOPE_BEGIN, offset, 1};
    }
    if (c == ')') {
      return (struct tibs_token){TIBS_SCOPE_END, offset, 1};
    }
  }
  return (struct tibs_token){.type = TIBS_EOS, .offset = offset, .len = 0};
}

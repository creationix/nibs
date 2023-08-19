#include <stdbool.h>
#include <stdint.h>

enum token_type {
  TOKEN_ERROR = 0,
  TOKEN_STRING,
  TOKEN_BYTES,
  TOKEN_NUMBER,
  TOKEN_TRUE,
  TOKEN_FALSE,
  TOKEN_NULL,
  TOKEN_NAN,
  TOKEN_INF,
  TOKEN_NINF,
  TOKEN_REF,
  TOKEN_COLON,
  TOKEN_COMMA,
  TOKEN_LBRACE,
  TOKEN_RBRACE,
  TOKEN_LBRACKET,
  TOKEN_RBRACKET,
  TOKEN_LPAREN,
  TOKEN_RPAREN,
  TOKEN_EOF,
};

struct token_result {
  enum token_type type;
  int pos;
  int len;
};

struct token_result tibs_next_token(const char* input, int len, int pos);

// Consume a sequence of zero or more digits [0-9]
static void consume_digits(const char** firstp, const char* last) {
  const char* first = *firstp;
  while (first < last && *first >= '0' && *first <= '9') {
    first++;
  }
  *firstp = first;
}

static bool consume_optional(const char** firstp, const char* last, char c) {
  const char* first = *firstp;
  if (first < last && *first == c) {
    *firstp = first + 1;
    return true;
  }
  return false;
}

static bool consume_optionals(const char** firstp,
                              const char* last,
                              char c1,
                              char c2) {
  const char* first = *firstp;
  if (first < last) {
    if (*first == c1 || *first == c2) {
      *firstp = first + 1;
      return true;
    }
  }
  return false;
}

struct token_result tibs_next_token(const char* input, int len, int pos) {
  const char* first = input + pos;
  const char* last = input + len;
  while (first < last) {
    char c = *first++;

    // Skip whitespace
    if (c == '\r' || c == '\n' || c == '\t' || c == ' ') {
      continue;
    }

    // Skip comments
    if (c == '/' && first < last && *first == '/') {
      first++;
      while (first < last) {
        c = *first++;
        if (c == '\r' || c == '\n') {
          break;
        }
      }
      continue;
    }

    if (c == '[') {
      return (struct token_result){
          .type = TOKEN_LBRACKET,
          .pos = first - input - 1,
          .len = 1,
      };
    }
    if (c == ']') {
      return (struct token_result){
          .type = TOKEN_RBRACKET,
          .pos = first - input - 1,
          .len = 1,
      };
    }
    if (c == '{') {
      return (struct token_result){
          .type = TOKEN_LBRACE,
          .pos = first - input - 1,
          .len = 1,
      };
    }
    if (c == '}') {
      return (struct token_result){
          .type = TOKEN_RBRACE,
          .pos = first - input - 1,
          .len = 1,
      };
    }
    if (c == ':') {
      return (struct token_result){
          .type = TOKEN_COLON,
          .pos = first - input - 1,
          .len = 1,
      };
    }
    if (c == ',') {
      return (struct token_result){
          .type = TOKEN_COMMA,
          .pos = first - input - 1,
          .len = 1,
      };
    }
    if (c == '(') {
      return (struct token_result){
          .type = TOKEN_LPAREN,
          .pos = first - input - 1,
          .len = 1,
      };
    }
    if (c == ')') {
      return (struct token_result){
          .type = TOKEN_RPAREN,
          .pos = first - input - 1,
          .len = 1,
      };
    }
    return (struct token_result){
        .type = TOKEN_ERROR,
        .pos = first - input - 1,
        .len = 1,
    };
  }
  return (struct token_result){
      .type = TOKEN_EOF,
      .pos = first - input,
      .len = 1,
  };
}

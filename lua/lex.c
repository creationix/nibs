#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

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

enum token_type tibs_next_token(const char* input, int len, int pos, int* out_pos, int* out_len);

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

enum token_type tibs_next_token(const char* input, int len, int pos, int* out_pos, int* out_len) {
  const char* first = input + pos;
  const char* last = input + len;
  while (first < last) {
    switch (*first++) {
      // Skip whitespace
      case '\r':
      case '\n':
      case '\t':
      case ' ':
        continue;

      // Skip comments
      case '/':
        if (first < last && *first == '/') {
          first++;
          while (first < last) {
            char c = *first++;
            if (c == '\r' || c == '\n') {
              break;
            }
          }
          continue;
        }
        break;

      case '[': {
        const char* start = first - 1;
        if (first < last && *first == '#') {
          first = first + 1;
        }
        *out_pos = start - input;
        *out_len = first - start;
        return TOKEN_LBRACKET;
      }
      case ']':
        *out_pos = first - input - 1;
        *out_len = 1;
        return TOKEN_RBRACKET;
      case '{':
        *out_pos = first - input - 1;
        *out_len = 1;
        return TOKEN_LBRACE;
      case '}':
        *out_pos = first - input - 1;
        *out_len = 1;
        return TOKEN_RBRACE;
      case ':':
        *out_pos = first - input - 1;
        *out_len = 1;
        return TOKEN_COLON;
      case ',':
        *out_pos = first - input - 1;
        *out_len = 1;
        return TOKEN_COMMA;
      case '(':
        *out_pos = first - input - 1;
        *out_len = 1;
        return TOKEN_LPAREN;
      case ')':
        *out_pos = first - input - 1;
        *out_len = 1;
        return TOKEN_RPAREN;
      case '"': {
        // Parse Strings
        const char* start = first - 1;
        while (first < last) {
          char c = *first++;
          if (c == '"') {
            *out_pos = start - input;
            *out_len = first - start;
            return TOKEN_STRING;
          } else if (c == '\\') {
            first++;
          } else if (c == '\r' || c == '\n') {
            // newline is not allowed
            break;
          }
        }
        break;
      }
      case '|': {
        const char* start = first - 1;
        while (first < last) {
          char c = *first++;
          if (c == '|') {
            *out_pos = start - input;
            *out_len = first - start;
            return TOKEN_BYTES;
          }
          if (c == '\r' || c == '\n') {
            // newline is not allowed
            break;
          }
        }
      }
      case '-':
        if (first + 3 < last && first[0] == 'i' && first[1] == 'n' &&
            first[2] == 'f') {
          first += 3;
          *out_pos = first - input - 4;
          *out_len = 4;
          return TOKEN_NINF;
        }
        if (first >= last || *first < '0' || *first > '9')
          break;
      case '0':
      case '1':
      case '2':
      case '3':
      case '4':
      case '5':
      case '6':
      case '7':
      case '8':
      case '9': {
        const char* start = first - 1;
        consume_digits(&first, last);
        if (consume_optional(&first, last, '.')) {
          consume_digits(&first, last);
        }
        if (consume_optionals(&first, last, 'e', 'E')) {
          consume_optionals(&first, last, '+', '-');
          consume_digits(&first, last);
        }
        *out_pos = start - input;
        *out_len = first - start;
        return TOKEN_NUMBER;
      }
      case 't':
        if (first + 3 < last && first[0] == 'r' && first[1] == 'u' &&
            first[2] == 'e') {
          first += 3;
          *out_pos = first - input - 4;
          *out_len = 4;
          return TOKEN_TRUE;
        }
        break;
      case 'f':
        if (first + 4 < last && first[0] == 'a' && first[1] == 'l' &&
            first[2] == 's' && first[3] == 'e') {
          first += 4;
          *out_pos = first - input - 5;
          *out_len = 5;
          return TOKEN_FALSE;
        }
      case 'n':
        if (first + 3 < last && first[0] == 'u' && first[1] == 'l' &&
            first[2] == 'l') {
          first += 3;
          *out_pos = first - input - 4;
          *out_len = 4;
          return TOKEN_NULL;
        }
        if (first + 2 < last && first[0] == 'a' && first[1] == 'n') {
          first += 2;
          *out_pos = first - input - 3;
          *out_len = 3;
          return TOKEN_NAN;
        }
      case 'i':
        if (first + 2 < last && first[0] == 'n' && first[1] == 'f') {
          first += 2;
          *out_pos = first - input - 3;
          *out_len = 3;
          return TOKEN_INF;
        }
      case '&': {
        const char* start = first - 1;
        consume_digits(&first, last);
        if (first > start + 1) {
          *out_pos = start - input;
          *out_len = first - start;
          return TOKEN_REF;
        }
      }
    };

    // Error
    *out_pos = first - input - 1;
    *out_len = 1;
    return TOKEN_ERROR;
  }
  *out_pos = first - input;
  *out_len = 0;
  return TOKEN_EOF;
}

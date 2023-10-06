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

struct lexer_state {
  const char* first;
  const char* current;
  const char* last;
};

enum token_type tibs_next_token(struct lexer_state* S);

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

enum token_type tibs_next_token(struct lexer_state* S) {
  const char* last = S->last;
  while (S->current < last) {
    switch (S->current[0]) {
      // Skip whitespace
      case '\r':
      case '\n':
      case '\t':
      case ' ':
        S->current++;
        continue;

      // Skip comments
      case '/':
        if (S->current < last && S->current[1] == '/') {
          S->current += 2;
          while (S->current < last) {
            char c = S->current++[0];
            if (c == '\r' || c == '\n') {
              break;
            }
          }
          continue;
        }
        break;

      case '[': {
        S->first = S->current;
        if (S->current < last && S->current[1] == '#') {
          S->current += 2;
        } else {
          S->current++;
        }
        return TOKEN_LBRACKET;
      }
      case ']':
        S->first = S->current++;
        return TOKEN_RBRACKET;
      case '{':
        S->first = S->current++;
        return TOKEN_LBRACE;
      case '}':
        S->first = S->current++;
        return TOKEN_RBRACE;
      case ':':
        S->first = S->current++;
        return TOKEN_COLON;
      case ',':
        S->first = S->current++;
        return TOKEN_COMMA;
      case '(':
        S->first = S->current++;
        return TOKEN_LPAREN;
      case ')':
        S->first = S->current++;
        return TOKEN_RPAREN;
      case '"': {
        // Parse Strings
        S->first = S->current++;
        while (S->current < last) {
          char c = S->current++[0];
          if (c == '"') {
            return TOKEN_STRING;
          } else if (c == '\\') {
            S->current++;
          } else if (c == '\r' || c == '\n') {
            // newline is not allowed
            break;
          }
        }
        break;
      }
      case '-':
        if (S->current + 3 < last &&
            S->current[1] == 'i' && S->current[2] == 'n' &&
            S->current[3] == 'f') {
          S->first = S->current;
          S->current += 4;
          return TOKEN_NINF;
        }
      case '0':
      case '1':
      case '2':
      case '3':
      case '4':
      case '5':
      case '6':
      case '7':
      case '8':
      case '9':
        S->first = S->current++;

        consume_digits(&S->current, last);
        if (consume_optional(&S->current, last, '.')) {
          consume_digits(&S->current, last);
        }
        if (consume_optionals(&S->current, last, 'e', 'E')) {
          consume_optionals(&S->current, last, '+', '-');
          consume_digits(&S->current, last);
        }
        return TOKEN_NUMBER;
      case 'i':
        if (S->current + 3 < last && S->current[1] == 'n' &&
            S->current[2] == 'f') {
          S->first = S->current;
          S->current += 3;
          return TOKEN_INF;
        }
      case 'n':
        if (S->current + 3 < last && S->current[1] == 'u' &&
            S->current[2] == 'l' && S->current[3] == 'l') {
          S->first = S->current;
          S->current += 4;
          return TOKEN_NULL;
        }
        if (S->current + 2 < last && S->current[1] == 'a' &&
            S->current[2] == 'n') {
          S->first = S->current;
          S->current += 3;
          return TOKEN_NAN;
        }
      case '|':
        S->first = S->current++;
        while (S->current < last) {
          char c = S->current++[0];
          if (c == '|') {
            return TOKEN_BYTES;
          }
          if (c == '\r' || c == '\n') {
            // newline is not allowed
            break;
          }
        }

      case 't':
        if (S->current + 3 < last && S->current[1] == 'r' &&
            S->current[2] == 'u' && S->current[3] == 'e') {
          S->first = S->current;
          S->current += 4;
          return TOKEN_TRUE;
        }
        break;
      case 'f':
        if (S->current + 4 < last && S->current[1] == 'a' &&
            S->current[2] == 'l' && S->current[3] == 's' &&
            S->current[4] == 'e') {
          S->first = S->current;
          S->current += 5;
          return TOKEN_FALSE;
        }
        case '&': {
          S->first = S->current++;
          consume_digits(&(S->current), last);
          if (S->current > S->first) {
            return TOKEN_REF;
          }
        }
    };

    // Error
    S->first = S->current++;
    return TOKEN_ERROR;
  }
  S->first = S->current;
  return TOKEN_EOF;
}

// Creator:  creationix
// Maintainer: creationix
// Last Change: 2023-06-16T02:09:39.855Z
// Description: A parser for the TIBS format

enum tibs_type {
    TIBS_NULL,
    TIBS_BOOLEAN,
    TIBS_NUMBER,
    TIBS_BYTES,
    TIBS_STRING,
    TIBS_REF,
    TIBS_MAP_BEGIN,
    TIBS_MAP_END,
    TIBS_LIST_BEGIN,
    TIBS_LIST_END,
    TIBS_SCOPE_BEGIN,
    TIBS_SCOPE_END,
    TIBS_EOS
};

// Check if one null terminated string begins with another
static int starts_with(const char* prefix, const char* str) {
    while (*prefix && *prefix == *str) {
        prefix++;
        str++;
    }
    return *prefix == 0;
}

struct tibs_token {
    enum tibs_type type;
    int offset;
    int len;
};

typedef struct tibs_token token_t;

// `tibs` is a null terminated string
// `offset` is an offset into that string to start parsing
token_t tibs_parse(const char* tibs, int offset) {
    for (;tibs[offset];offset++) {
        if (starts_with("null", tibs + offset)) {
            return (token_t){TIBS_NULL, offset, 4};
        }
        if (starts_with("true", tibs + offset)) {
            return (token_t){TIBS_BOOLEAN, offset, 4};
        }
        if (starts_with("false", tibs + offset)) {
            return (token_t){TIBS_BOOLEAN, offset, 5};
        }
        if (starts_with("-inf", tibs + offset)) {
            return (token_t){TIBS_NUMBER, offset, 4};
        }
        if (starts_with("inf", tibs + offset)) {
            return (token_t){TIBS_NUMBER, offset, 3};
        }
        if (starts_with("nan", tibs + offset)) {
            return (token_t){TIBS_NUMBER, offset, 3};
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
            return (token_t){TIBS_NUMBER, offset, len};
        }
        if (tibs[offset] == '"') {
            int len = 1;
            while (tibs[offset + len] != '"') {
                if (tibs[offset + len] == '\\') {
                    len++;
                }
                len++;
            }
            return (token_t){TIBS_STRING, offset, len + 1};
        }
        if (tibs[offset] == '<') {
            int len = 1;
            while (tibs[offset + len] != '>') {
                len++;
            }
            return (token_t){TIBS_BYTES, offset, len + 1};
        }
        if (tibs[offset] == '&') {
            int len = 1;
            while (tibs[offset + len] >= '0' && tibs[offset + len] <= '9') {
                len++;
            }
            return (token_t){TIBS_REF, offset, len};
        }
        if (tibs[offset] == '[') {
            int len = tibs[offset + 1] == '#' ? 2 : 1;
            return (token_t){TIBS_LIST_BEGIN, offset, len};
        }
        if (tibs[offset] == ']') {
            return (token_t){TIBS_LIST_END, offset, 1};
        }
        if (tibs[offset] == '{') {
            int len = tibs[offset + 1] == '#' ? 2 : 1;
            return (token_t){TIBS_MAP_BEGIN, offset, len};
        }
        if (tibs[offset] == '}') {
            return (token_t){TIBS_MAP_END, offset, 1};
        }
        if (tibs[offset] == '(') {
            return (token_t){TIBS_SCOPE_BEGIN, offset, 1};
        }
        if (tibs[offset] == ')') {
            return (token_t){TIBS_SCOPE_END, offset, 1};
        }
    }
    return (token_t){.type = TIBS_EOS, .offset = offset, .len = 0};
}

static void on_number(void* state, const char* start, const char* end) {
    printf("on_number      %.*s\n", (int)(end - start), start);
}
static void on_boolean(void* state, const char* start) {
    printf("on_boolean     %.*s\n", *start == 't' ? 4 : 5, start);
}
static void on_null(void* state, const char* start) {
    printf("on_null        %.*s\n", 4, start);
}
static void on_bytes(void* state, const char* start, const char* end) {
    printf("on_bytes       %.*s\n", (int)(end - start), start);
}
static void on_string(void* state, const char* start, const char* end) {
    printf("on_string      %.*s\n", (int)(end - start), start);
}
static void on_ref(void* state, const char* start, const char* end) {
    printf("on_ref         %.*s\n", (int)(end - start), start);
}
static void on_map_start(void* state, const char* start, const char* end) {
    printf("on_map_start   %.*s\n", (int)(end - start), start);
}
static void on_map_stop(void* state, const char* start) {
    printf("on_map_stop    %1s\n", start);
}
static void on_list_start(void* state, const char* start, const char* end) {
    printf("on_list_start  %.*s\n", (int)(end - start), start);
}
static void on_list_stop(void* state, const char* start) {
    printf("on_list_stop   %1s\n", start);
}
static void on_scope_start(void* state, const char* start) {
    printf("on_scope_start %1s\n", start);
}
static void on_scope_stop(void* state, const char* start) {
    printf("on_scope_stop  %1s\n", start);
}

int main() {
    struct tibs_events events = {
        .on_number = on_number,
        .on_boolean = on_boolean,
        .on_null = on_null,
        .on_bytes = on_bytes,
        .on_string = on_string,
        .on_ref = on_ref,
        .on_map_start = on_map_start,
        .on_map_stop = on_map_stop,
        .on_list_start = on_list_start,
        .on_list_stop = on_list_stop,
        .on_scope_start = on_scope_start,
        .on_scope_stop = on_scope_stop,
    };

    FILE * fp;
    char * line = NULL;
    size_t len = 0;
    int read;

    fp = fopen("../fixtures/tibs-fixtures.txt", "r");
    if (fp == NULL)
        exit(EXIT_FAILURE);

    while ((read = getline(&line, &len, fp)) != -1) {
        printf("\n-> %.*s", read, line);
        tibs_parse(&events, line, read, NULL);
    }

    fclose(fp);
    if (line)
        free(line);

}
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

typedef void (*tibs_on_slice)(void* state, const char* start, const char* end);
typedef void (*tibs_on_start)(void* state, const char* start);

struct tibs_events {
    tibs_on_slice on_number;
    tibs_on_start on_boolean;
    tibs_on_start on_null;
    tibs_on_slice on_bytes;
    tibs_on_slice on_string;
    tibs_on_start on_map_start;
    tibs_on_start on_map_stop;
    tibs_on_start on_list_start;
    tibs_on_start on_list_stop;
    tibs_on_start on_scope_start;
    tibs_on_start on_scope_stop;
};

static bool starts_with(const char* prefix, const char* start, const char* end) {
    size_t len = end - start;
    return strlen(prefix) <= len && memcmp(prefix, start, len) == 0;
}

void tibs_parse(struct tibs_events* events, const char* start, size_t len, void* state) {
    const char* pos = start;
    const char* end = start + len;
    while (pos <= end) {
        if (starts_with("null", pos, end)) {
            events->on_null(state, pos);
            pos += 4;
            continue;
        }
        if (starts_with("true", pos, end)) {
            events->on_boolean(state, pos);
            pos += 4;
            continue;
        }
        if (starts_with("false", pos, end)) {
            events->on_boolean(state, pos);
            pos += 5;
            continue;
        }
        if (starts_with("-inf", pos, end)) {
            events->on_number(state, pos, pos + 4);
            pos += 4;
            continue;
        }
        if (starts_with("inf", pos, end)) {
            events->on_number(state, pos, pos + 3);
            pos += 3;
            continue;
        }
        if (starts_with("nan", pos, end)) {
            events->on_number(state, pos, pos + 3);
            pos += 3;
            continue;
        }
        if (pos[9] == '[') {
            events->on_list_start(state, pos);
            pos += 10;
            continue;
        }
        switch(*pos) {
            case '[':
                events->on_list_start(state, pos++);
                continue;
            case ']':
                events->on_list_stop(state, pos++);
                continue;
            case '{':
                events->on_map_start(state, pos++);
                continue;
            case '}':
                events->on_map_stop(state, pos++);
                continue;
            case '(':
                events->on_scope_start(state, pos++);
                continue;
            case ')':
                events->on_scope_stop(state, pos++);
                continue;
            case '0': case '1': case '2': case '3': case '4':
            case '5': case '6': case '7': case '8': case '9':
            case '-': {
                if (pos + 4 <= end && pos[1] == 'i' && pos[2] == 'n' && pos[3] == 'f') {
                    events->on_number(state, pos, pos + 4);
                    pos += 4;
                    continue;
                }
                const char* pos2 = pos + 1;
                start: switch(*pos2) {
                    case '0': case '1': case '2': case '3': case '4':
                    case '5': case '6': case '7': case '8': case '9':
                    case '-': case '+': case 'e': case 'E': case '.':
                        pos2++;
                        goto start;
                }
                events->on_number(state, pos, pos2);
                pos = pos2;
                continue;
            }
            case 'i': 
                if (pos + 3 <= end && pos[1] == 'n' && pos[2] == 'f') {
                    events->on_number(state, pos, pos + 3);
                    pos += 3;
                    continue;
                }
            case 't':
                events->on_boolean(state, pos);
                pos += 4;
                continue;
            case 'f':
                events->on_boolean(state, pos);
                pos += 5;
                continue;
            case 'n':
                if (pos + 3 <= end && pos[1] == 'a' && pos[2] == 'n') {
                    events->on_number(state, pos, pos + 3);
                    pos += 3;
                    continue;
                }
                events->on_null(state, pos);
                pos += 4;
                continue;
            case '<': {
                const char* pos2 = pos + 1;
                while (pos2 < end && *pos2++ != '>');
                events->on_bytes(state, pos, pos2);
                pos = pos2;
                continue;
            }
            case '"': {
                const char* pos2 = pos + 1;
                while (pos2 <= end) {
                    if (*pos2 == '\\') {
                        pos2 += 2;
                        if (pos2 >= end) break;
                    }
                    if (*pos2++ == '"') break;
                }
                events->on_string(state, pos, pos2);
                pos = pos2;
                continue;
            }
            default:
                pos++;
                continue;
        }
    }
}

static void on_number(void* state, const char* start, const char* end) {
    printf("on_number %.*s\n", (int)(end - start), start);
}
static void on_boolean(void* state, const char* start) {
    printf("on_boolean %.*s\n", *start == 't' ? 4 : 5, start);
}
static void on_null(void* state, const char* start) {
    printf("on_null %.*s\n", 4, start);
}
static void on_bytes(void* state, const char* start, const char* end) {
    printf("on_bytes %.*s\n", (int)(end - start), start);
}
static void on_string(void* state, const char* start, const char* end) {
    printf("on_string %.*s\n", (int)(end - start), start);
}
static void on_map_start(void* state, const char* start) {
    printf("on_map_start %p\n", start);
}
static void on_map_stop(void* state, const char* start) {
    printf("on_map_stop %p\n", start);
}
static void on_list_start(void* state, const char* start) {
    printf("on_list_start %p\n", start);
}
static void on_list_stop(void* state, const char* start) {
    printf("on_list_stop %p\n", start);
}
static void on_scope_start(void* state, const char* start) {
    printf("on_scope_start %p\n", start);
}
static void on_scope_stop(void* state, const char* start) {
    printf("on_scope_stop %p\n", start);
}

int main() {
    struct tibs_events events = {
        .on_number = on_number,
        .on_boolean = on_boolean,
        .on_null = on_null,
        .on_bytes = on_bytes,
        .on_string = on_string,
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
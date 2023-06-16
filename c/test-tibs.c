#include "tibs.h"
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

static const char* tibs_type_names[] = {
    "null",
    "boolean",
    "number",
    "bytes",
    "string",
    "ref",
    "map_begin",
    "map_end",
    "list_begin",
    "list_end",
    "scope_begin",
    "scope_end",
    "eos"
};

int main() {

    FILE * fp;
    char * line = NULL;
    size_t len = 0;
    int read;

    fp = fopen("../fixtures/tibs-fixtures.txt", "r");
    assert(fp);

    while ((read = getline(&line, &len, fp)) != -1) {
        printf("\n-> %.*s", read, line);
        int offset = 0;
        while (1) {
            struct tibs_token token = tibs_parse(line, offset);
            if (token.type == TIBS_EOS) break;
            printf("  %s %.*s\n", tibs_type_names[token.type], token.len, line + token.offset);
            offset = token.offset + token.len;
        }
    }

    fclose(fp);
    if (line)
        free(line);

}
#include "tibs.h"
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

int main() {

    FILE * fp;
    char * line = NULL;
    size_t len = 0;
    int read;

    fp = fopen("../fixtures/tibs-fixtures.txt", "r");
    assert(fp);

    while ((read = getline(&line, &len, fp)) != -1) {
        printf("\n-> %.*s", read, line);
        struct tibs_token token;
        int offset = 0;
        do {
            token = tibs_parse(line, offset);
            printf("  %d %d %d\n", token.type, token.offset, token.len);
            offset = token.offset + token.len;
        } while (token.type != TIBS_EOS);
    }

    fclose(fp);
    if (line)
        free(line);

}
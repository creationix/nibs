# CC=musl-gcc -static
# CFLAGS=-std=c99 -Os -Wall -Wextra -Werror

CC=gcc
CFLAGS=-std=c99 -Og -Wall -Wextra -Werror -g

all-tests: tibs-tests nibs-tests

nibs-tests: test-nibs
	./test-nibs ../fixtures/tibs-fixtures.txt | hd
	./test-nibs ../fixtures/decoder-fixtures.tibs | hd
	./test-nibs ../fixtures/encoder-fixtures.tibs | hd
	./test-nibs ../fixtures/multi-tests.tibs | hd

tibs-tests: test-tibs 
	./test-tibs ../fixtures/tibs-fixtures.txt
	./test-tibs ../fixtures/decoder-fixtures.tibs
	./test-tibs ../fixtures/encoder-fixtures.tibs
	./test-tibs ../fixtures/multi-tests.tibs

test-tibs: test-tibs.c tibs.c tibs.h 
	$(CC) $(CFLAGS) test-tibs.c tibs.c -o test-tibs
test-nibs: test-nibs.c nibs.c arena.c tibs.c arena.h nibs.h tibs.h
	$(CC) $(CFLAGS) test-nibs.c nibs.c arena.c tibs.c -o test-nibs

clean:
	rm -f test-tibs test-nibs
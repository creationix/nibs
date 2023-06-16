CFLAGS=-std=c99 -g -Wall -Wextra -Werror -pedantic

all-tests: tibs-tests

tibs-tests: test-tibs 
	./test-tibs ../fixtures/tibs-fixtures.txt
	./test-tibs ../fixtures/decoder-fixtures.tibs
	./test-tibs ../fixtures/encoder-fixtures.tibs
	./test-tibs ../fixtures/multi-tests.tibs

test-tibs: test-tibs.c tibs.c tibs.h 
	gcc $(CFLAGS) test-tibs.c tibs.c -o test-tibs
test-nibs: test-nibs.c nibs.c arena.c arena.h nibs.h
	gcc $(CFLAGS) test-nibs.c nibs.c arena.c -o test-nibs

clean:
	rm -f test-tibs test-nibs
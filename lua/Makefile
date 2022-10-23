test:
	luvit tests/test-bytes.lua
	luvit tests/test-text-format.lua
	luvit tests/test-xxhash.lua
	luvit tests/test-trie.lua

publish: test
	lit publish nibs.lua

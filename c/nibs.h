
#ifndef NIBS_H
#define NIBS_H

enum nibs_types {
    NIBS_ZIGZAG = 0,
    NIBS_FLOAT = 1,
    NIBS_SIMPLE = 2,
    NIBS_REF = 3,
    NIBS_BYTES = 8,
    NIBS_UTF8 = 9,
    NIBS_HEXSTRING = 10,
    NIBS_LIST = 11,
    NIBS_MAP = 12,
    NIBS_ARRAY = 13,
    NIBS_TRIE = 14,
    NIBS_SCOPE = 15,
};

enum nibs_subtypes {
    NIBS_FALSE = 0,
    NIBS_TRUE = 1,
    NIBS_NULL = 2,
};

#endif

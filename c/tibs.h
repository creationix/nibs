#ifndef TIBS_H
#define TIBS_H

// Creator:  creationix
// Maintainer: creationix
// Last Change: 2023-06-16T02:09:39.855Z
// Description: A parser for the TIBS format

// TIBS is a simple text-based format for representing NIBS data in textual format.
// It's a superset of JSON syntax so it can be also be used as a JSON parser.

// Tibs Types
enum tibs_type {
    TIBS_NULL,        // null
    TIBS_BOOLEAN,     // true or false
    TIBS_NUMBER,      // -123.456e-78 or -inf or inf or nan
    TIBS_BYTES,       // <0123456789abcdef>
    TIBS_STRING,      // "hello world"
    TIBS_REF,         // &123
    TIBS_MAP_BEGIN,   // { or {# 
    TIBS_MAP_END,     // }
    TIBS_LIST_BEGIN,  // [ or [#
    TIBS_LIST_END,    // ]
    TIBS_SCOPE_BEGIN, // (
    TIBS_SCOPE_END,   // )
    TIBS_EOS          // End of string
};

struct tibs_token {
    enum tibs_type type;
    int offset;
    int len;
};

// `tibs` is a null terminated string
// `offset` is an offset into that string to start parsing
struct tibs_token tibs_parse(const char* tibs, int offset);

#endif // TIBS_H
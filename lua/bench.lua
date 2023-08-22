local Nibs = require 'nibs'
local Tibs = Nibs.Tibs

local ffi = require 'ffi'
ffi.cdef [[
    typedef long time_t;
    typedef long suseconds_t;
    struct timeval {
        time_t       tv_sec;   /* seconds since Jan. 1, 1970 */
        suseconds_t  tv_usec;  /* and microseconds */
    };
    struct timezone {
        int     tz_minuteswest; /* of Greenwich */
        int     tz_dsttime;     /* type of dst correction to apply */
    };
    int gettimeofday(struct timeval *tv, struct timezone *tz);
]]

local function hrtime()
  local tm = ffi.new("struct timeval")
  ffi.C.gettimeofday(tm, nil)
  return tonumber(tm.tv_sec) * 1000000 + tonumber(tm.tv_usec)
end

---@param filename string
---@param log_it? boolean
local function parse(filename, log_it)
  local fd = assert(io.open(filename))
  local tibs = assert(fd:read "*a")
  fd:close()

  local before = hrtime()
  for t, f, l in Tibs.lexer(tibs) do
    -- print(string.format("%s %d %d", t, f, l))
    if t == "error" or t == 0 then
      error(Tibs.format_syntax_error(tibs, f+1, filename))
    end
    if log_it then
      print(string.format("% 6s % 4d % 4d %s", t, f, l, tibs:sub(f + 1, l)))
    end
  end
  local after = hrtime()
  print(string.format("lexer: %.1fms", (after - before)/1000))
end


local L = ffi.load("./lex.so")
ffi.cdef[[
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
]]

function Tibs.lexer(json)
  local data = ffi.cast("const char*", json)
  local len = #json
  local S = ffi.new "struct lexer_state"
  S.first = data
  S.current = S.first
  S.last = data + len
  return function ()
    -- print(string.format("pos=%d len=%s", pos, len))
    local token_index = L.tibs_next_token(S)
    -- print(string.format("token_index=%d first=%d current=%d last=%d",
    --   tonumber(token_index),
    --   S.first - data,
    --   S.current - data,
    --   S.last - data
    -- ))
    if token_index == ffi.C.TOKEN_EOF then return end
    -- print(string.format("token_index=%d, out_pos=%d out_len=%d", tonumber(token_index), out_pos[0], out_len[0]))
    local p = S.first - data
    local l = S.current - data
    -- print(string.format("pos=%d", pos))
    return token_index, p, l
  end
end

parse("../fixtures/encoder-fixtures.tibs", true)
parse("../fixtures/encoder-fixtures.tibs", false)
parse("../bench/data-formatted.json", false)

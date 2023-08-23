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

local p = require('deps/pretty-print').prettyPrint

local function bench(filename)
  local fd = assert(io.open(filename))
  local tibs = assert(fd:read "*a")
  assert(fd:close())
  local doc, err = Tibs.parse(tibs, filename)
  p { doc = doc, err = err }
end


bench("../fixtures/encoder-fixtures.tibs")

-- for _ = 1, 10 do
--   parse(c_lexer, "../fixtures/encoder-fixtures.tibs", false)
--   parse(c_lexer, "../fixtures/decoder-fixtures.tibs", false)
-- end
--   print("\nC")
--   parse(c_lexer, "../../www.justsunnies.com.json", false)
--   parse(c_lexer, "../bench/data.json", false)
--   parse(c_lexer, "../bench/data-formatted.json", false)
--   print("\nL")
--   parse(l_lexer, "../fixtures/encoder-fixtures.tibs", false)
--   parse(l_lexer, "../fixtures/decoder-fixtures.tibs", false)
--   parse(l_lexer, "../../www.justsunnies.com.json", false)
--   parse(l_lexer, "../bench/data.json", false)
--   parse(l_lexer, "../bench/data-formatted.json", false)
-- end

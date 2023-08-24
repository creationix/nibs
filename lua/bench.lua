local Tibs = require 'tibs'

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
local cjson = require 'deps/cjson'

local function format_bytes(kb)
  if kb < 1024 then
    return string.format("%dKB", kb)
  else
    return string.format("%.1fMB", kb / 1024)
  end
end

local function bench(filename)
  local fd = assert(io.open(filename))
  local tibs = assert(fd:read "*a")
  assert(fd:close())
  collectgarbage "stop"
  collectgarbage "collect"
  collectgarbage "collect"
  local before_mem = collectgarbage "count"
  local before = hrtime()
  local doc = assert(Tibs.decode(tibs, filename))
  local after = hrtime()
  local after_mem = collectgarbage "count"
  collectgarbage "collect"
  collectgarbage "collect"
  local after_mem2 = collectgarbage "count"
  print(string.format("% 40s -> table:  % 5.1fms %s %s",
    filename, (after - before) / 1000,
    format_bytes(after_mem - before_mem),
    format_bytes(after_mem2 - before_mem)
  ))
  before_mem = collectgarbage "count"
  before = hrtime()
  local encoded = assert(Tibs.encode(doc))
  -- local encoded = assert(cjson.encode(doc))
  after = hrtime()
  after_mem = collectgarbage "count"
  collectgarbage "collect"
  collectgarbage "collect"
  after_mem2 = collectgarbage "count"
  print(string.format("% 40s -> string(%d): % 5.1fms %s %s",
    filename, #encoded, (after - before) / 1000,
    format_bytes(after_mem - before_mem),
    format_bytes(after_mem2 - before_mem)
  ))
  collectgarbage "restart"
end


for _ = 1, 10 do
  -- bench "../fixtures/encoder-fixtures.tibs"
  -- bench "../fixtures/decoder-fixtures.tibs"
  -- bench "../../www.justsunnies.com.json"
  bench "../bench/data.json"
end
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

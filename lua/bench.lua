-- Add .local prefix to paths
package.cpath = string.format(
  "%s/.local/lib/lua/5.1/?.so;%s",
  os.getenv("HOME"),
  package.cpath)
package.path = string.format(
  "%s/.local/share/lua/5.1/?.lua;%s",
  os.getenv("HOME"),
  package.path)

local p = require('deps/pretty-print').prettyPrint
-- local cjson_ffi = require 'deps/cjson'
local cjson_resty = require 'cjson'

do -- Polyfill for luajit without __pairs and __ipairs extensions
  local triggered = false
  pairs(setmetatable({}, {
    __pairs = function()
      triggered = true
      return function() end
    end
  }))
  if not triggered then
    print "Polyfilling pairs"
    function _G.pairs(t)
      local mt = getmetatable(t)
      if mt and mt.__pairs then
        return mt.__pairs(t)
      else
        return next, t, nil
      end
    end
  end
  triggered = false
  ipairs(setmetatable({}, {
    __ipairs = function()
      triggered = true
      return function() end
    end
  }))
  if not triggered then
    print "Polyfilling ipairs"
    function _G.ipairs(t)
      local mt = getmetatable(t)
      if mt and mt.__ipairs then
        return mt.__ipairs(t)
      else
        return next, t, nil
      end
    end
  end
end

local Tibs = require './tibs'

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
  ---@type {tv_sec:integer,tv_usec:integer}
  local tm = ffi.new("struct timeval")
  ffi.C.gettimeofday(tm, nil)
  return tonumber(tm.tv_sec) * 1000000 + tonumber(tm.tv_usec)
end

local function format_bytes(kb)
  if math.abs(kb) < 1024 then
    return string.format("%d KiB", kb)
  else
    return string.format("%.2f MiB", kb / 1024)
  end
end

local cached = {}
local function bench(filename)
  local tibs = cached[filename]
  if not tibs then
    local fd = assert(io.open(filename))
    tibs = assert(fd:read "*a")
    assert(fd:close())
    cached[filename] = tibs
  end
  print(string.format("\n\n%s (%s)\n",
    filename, format_bytes(#tibs/1024)))


  local function test(name, fn, ...)
    collectgarbage "stop"
    collectgarbage "collect"
    collectgarbage "collect"
    collectgarbage "collect"
    collectgarbage "collect"
    local before_mem = collectgarbage "count"
    local before = hrtime()
    local res = fn(...)
    local after = hrtime()
    local after_mem = collectgarbage "count"
    collectgarbage "collect"
    collectgarbage "collect"
    collectgarbage "collect"
    collectgarbage "collect"
    local after_mem2 = collectgarbage "count"
    print(string.format("% 30s % 7.1fms % 9s % 9s",
      name,
      (after - before) / 1000,
      format_bytes(after_mem - before_mem),
      format_bytes(after_mem2 - before_mem)
    ))
    collectgarbage "collect"
    collectgarbage "collect"
    collectgarbage "collect"
    collectgarbage "collect"
    collectgarbage "restart"
    return res
  end

  print(string.format("% 30s % 9s % 9s % 9s",
    "Action", "Duration", "Used","Kept"
  ))


  -- local small = test("Tibs.trim", Tibs.trim, tibs, filename)
  -- local doc1 = test("cjson_ffi.decode", cjson_ffi.decode, tibs)
  local doc2 = test("cjson_resty.decode", cjson_resty.decode, tibs)
  local doc3 = test("Tibs.decode", Tibs.decode, tibs)
  -- local enc1 = test("cjson_ffi.encode", cjson_ffi.encode, doc1, false)
  local enc2 = test("cjson_resty.encode", cjson_resty.encode, doc2)
  local enc3 = test("Tibs.encode", Tibs.encode, doc3)

  if #enc2 ~= #enc3 then
    print("\nencoded sizes mismatch:", #enc2, #enc3)
    for i = 1, math.max(#enc2, #enc3) do
      if enc2:byte(i) ~= enc3:byte(i) then
        -- print("cjson_ffi   = " .. enc1:sub(i - 20, i + 20))
        print("cjson_resty = " .. enc2:sub(i - 20, i + 20))
        print("tibs        = " .. enc3:sub(i - 20, i + 20))
        break
      end
    end
  end
end

function Tibs.trim(str, filename)
  local next_token = Tibs.next_token
  local ByteWriter = Tibs.ByteWriter
  local data = ffi.cast("uint8_t*", str)
  local len = #str
  local slice = ByteWriter.new(1024)
  local offset = 0
  local token, start
  while true do
    offset, token, start = next_token(data, offset, len)
    if offset < 0 then error(Tibs.format_syntax_error(str, -offset, filename)) end
    if token == "error" then error(Tibs.format_syntax_error(str, offset, filename)) end
    if token == "eos" then break end
    slice:write_bytes(data + start, offset - start)
  end
  return slice:to_string()
end

local files = {
  -- "../fixtures/encoder-fixtures.tibs",
  -- "../fixtures/decoder-fixtures.tibs",
  "../bench/corgis/website/datasets/json/tate/tate.json",
  "../bench/corgis/website/datasets/json/airlines/airlines.json",
  "../bench/corgis/website/datasets/json/school_scores/school_scores.json",
  "../bench/corgis/website/datasets/json/food/food.json",
  "../bench/corgis/website/datasets/json/suicide_attacks/suicide_attacks.json",
  "../bench/corgis/website/datasets/json/electricity/electricity.json",
  "../bench/corgis/website/datasets/json/injuries/injuries.json",
  "../bench/corgis/website/datasets/json/hydropower/hydropower.json",
  "../bench/corgis/website/datasets/json/construction_spending/construction_spending.json",
  "../bench/corgis/website/datasets/json/covid/covid.json",
  "../bench/corgis/website/datasets/json/earthquakes/earthquakes.json",
  "../bench/corgis/website/datasets/json/food_access/food_access.json",
  "../bench/corgis/website/datasets/json/weather/weather.json",
  "../bench/corgis/website/datasets/json/energy/energy.json",
  "../bench/corgis/website/datasets/json/health/health.json",
  "../bench/corgis/website/datasets/json/music/music.json",
  "../bench/corgis/website/datasets/json/aids/aids.json",
  "../bench/corgis/website/datasets/json/cancer/cancer.json",
  "../bench/corgis/website/datasets/json/medal_of_honor/medal_of_honor.json",
  "../bench/corgis/website/datasets/json/retail_services/retail_services.json",
  "../bench/corgis/website/datasets/json/publishers/publishers.json",
  "../bench/corgis/website/datasets/json/county_demographics/county_demographics.json",
  "../bench/corgis/website/datasets/json/cars/cars.json",
  "../bench/corgis/website/datasets/json/labor/labor.json",
  "../bench/corgis/website/datasets/json/police_shootings/police_shootings.json",
  "../bench/corgis/website/datasets/json/state_crime/state_crime.json",
  "../bench/corgis/website/datasets/json/slavery/slavery.json",
  "../bench/corgis/website/datasets/json/real_estate/real_estate.json",
  "../bench/corgis/website/datasets/json/hospitals/hospitals.json",
  "../bench/corgis/website/datasets/json/supreme_court/supreme_court.json",
  "../bench/corgis/website/datasets/json/state_fragility/state_fragility.json",
  "../bench/corgis/website/datasets/json/opioids/opioids.json",
  "../bench/corgis/website/datasets/json/drugs/drugs.json",
  "../bench/corgis/website/datasets/json/skyscrapers/skyscrapers.json",
  "../bench/corgis/website/datasets/json/finance/finance.json",
  "../bench/corgis/website/datasets/json/global_development/global_development.json",
  "../bench/corgis/website/datasets/json/ingredients/ingredients.json",
  "../bench/corgis/website/datasets/json/graduates/graduates.json",
  "../bench/corgis/website/datasets/json/classics/classics.json",
  "../bench/corgis/website/datasets/json/emissions/emissions.json",
  "../bench/corgis/website/datasets/json/wind_turbines/wind_turbines.json",
  "../bench/corgis/website/datasets/json/business_dynamics/business_dynamics.json",
  "../bench/corgis/website/datasets/json/broadway/broadway.json",
  "../bench/corgis/website/datasets/json/billionaires/billionaires.json",
  "../bench/corgis/website/datasets/json/election/election.json",
  "../bench/corgis/website/datasets/json/construction_permits/construction_permits.json",
  "../bench/corgis/website/datasets/json/state_demographics/state_demographics.json",
  "../bench/corgis/website/datasets/json/video_games/video_games.json",
}

for _ = 1, 1 do
  for _, filename in ipairs(files) do
    bench(filename)
  end
end

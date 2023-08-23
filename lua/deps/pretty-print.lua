--[[

Copyright 2014-2015 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]
--[[lit-meta
  name = "luvit/pretty-print"
  version = "2.1.1"
  homepage = "https://github.com/luvit/luvit/blob/master/deps/pretty-print.lua"
  description = "A lua value pretty printer and colorizer for terminals."
  tags = {"colors", "tty"}
  license = "Apache 2"
  author = { name = "Tim Caswell" }
]]


local prettyPrint, dump, strip, color, colorize, loadColors
local theme = {}
local useColors = false
local defaultTheme

local stdout, stdin, stderr, width

local quote, quote2, dquote, dquote2, obracket, cbracket, obrace, cbrace, comma, equals, controls

local themes = {
  -- nice color theme using 16 ansi colors
  [16] = {
    property = "0;37", -- white
    sep      = "1;30", -- bright-black
    braces   = "1;30", -- bright-black

    ["nil"]      = "1;30", -- bright-black
    boolean      = "0;33", -- yellow
    number       = "1;33", -- bright-yellow
    string       = "0;32", -- green
    quotes       = "1;32", -- bright-green
    escape       = "1;32", -- bright-green
    ["function"] = "0;35", -- purple
    thread       = "1;35", -- bright-purple

    table    = "1;34", -- bright blue
    userdata = "1;36", -- bright cyan
    cdata    = "0;36", -- cyan

    err       = "1;31", -- bright red
    success   = "1;33;42", -- bright-yellow on green
    failure   = "1;33;41", -- bright-yellow on red
    highlight = "1;36;44", -- bright-cyan on blue
  },
  -- nice color theme using ansi 256-mode colors
  [256] = {
    property = "38;5;253",
    braces   = "38;5;247",
    sep      = "38;5;240",

    ["nil"]      = "38;5;244",
    boolean      = "38;5;220", -- yellow-orange
    number       = "38;5;202", -- orange
    string       = "38;5;34", -- darker green
    quotes       = "38;5;40", -- green
    escape       = "38;5;46", -- bright green
    ["function"] = "38;5;129", -- purple
    thread       = "38;5;199", -- pink

    table    = "38;5;27", -- blue
    userdata = "38;5;39", -- blue2
    cdata    = "38;5;69", -- teal

    err       = "38;5;196", -- bright red
    success   = "38;5;120;48;5;22", -- bright green on dark green
    failure   = "38;5;215;48;5;52", -- bright red on dark red
    highlight = "38;5;45;48;5;236", -- bright teal on dark grey
  },
}

local special = {
  [7] = 'a',
  [8] = 'b',
  [9] = 't',
  [10] = 'n',
  [11] = 'v',
  [12] = 'f',
  [13] = 'r'
}

function strip(str)
  return string.gsub(str, '\027%[[^m]*m', '')
end

function loadColors(index)
  if index == nil then index = defaultTheme end

  -- Remove the old theme
  for key in pairs(theme) do
    theme[key] = nil
  end

  if index then
    local new = themes[index]
    if not new then error("Invalid theme index: " .. tostring(index)) end
    -- Add the new theme
    for key in pairs(new) do
      theme[key] = new[key]
    end
    useColors = true
  else
    useColors = false
  end

  quote    = colorize('quotes', "'", 'string')
  quote2   = colorize('quotes', "'")
  dquote   = colorize('quotes', '"', 'string')
  dquote2  = colorize('quotes', '"')
  obrace   = colorize('braces', '{ ')
  cbrace   = colorize('braces', '}')
  obracket = colorize('property', '[')
  cbracket = colorize('property', ']')
  comma    = colorize('sep', ', ')
  equals   = colorize('sep', ' = ')

  controls = {}
  for i = 0, 31 do
    local c = special[i]
    if not c then
      if i < 10 then
        c = "00" .. tostring(i)
      else
        c = "0" .. tostring(i)
      end
    end
    controls[i] = colorize('escape', '\\' .. c, 'string')
  end
  controls[92] = colorize('escape', '\\\\', 'string')
  controls[34] = colorize('escape', '\\"', 'string')
  controls[39] = colorize('escape', "\\'", 'string')
  for i = 128, 255 do
    local c
    if i < 100 then
      c = "0" .. tostring(i)
    else
      c = tostring(i)
    end
    controls[i] = colorize('escape', '\\' .. c, 'string')
  end

end

function color(colorName)
  return '\27[' .. (theme[colorName] or '0') .. 'm'
end

function colorize(colorName, string, resetName)
  return useColors and
      (color(colorName) .. tostring(string) .. color(resetName)) or
      tostring(string)
end

local function stringEscape(c)
  return controls[string.byte(c, 1)]
end

function dump(value, recurse, nocolor)
  local seen = {}
  local output = {}
  local offset = 0
  local stack = {}

  local function recalcOffset(index)
    for i = index + 1, #output do
      local m = string.match(output[i], "\n([^\n]*)$")
      if m then
        offset = #(strip(m))
      else
        offset = offset + #(strip(output[i]))
      end
    end
  end

  local function write(text, length)
    if not length then length = #(strip(text)) end
    -- Create room for data by opening parent blocks
    -- Start at the root and go down.
    local i = 1
    while offset + length > width and stack[i] do
      local entry = stack[i]
      if not entry.opened then
        entry.opened = true
        table.insert(output, entry.index + 1, "\n" .. string.rep("  ", i))
        -- Recalculate the offset
        recalcOffset(entry.index)
        -- Bump the index of all deeper entries
        for j = i + 1, #stack do
          stack[j].index = stack[j].index + 1
        end
      end
      i = i + 1
    end
    output[#output + 1] = text
    offset = offset + length
    if offset > width then
      return dump(stack)
    end
  end

  local function indent()
    stack[#stack + 1] = {
      index = #output,
      opened = false,
    }
  end

  local function unindent()
    stack[#stack] = nil
  end

  local function process(localValue)
    local typ = type(localValue)
    if typ == 'string' then
      if string.find(localValue, "'") and not string.find(localValue, '"') then
        write(dquote)
        write(string.gsub(localValue, '[%c\\\128-\255]', stringEscape))
        write(dquote2)
      else
        write(quote)
        write(string.gsub(localValue, "[%c\\'\128-\255]", stringEscape))
        write(quote2)
      end
    elseif typ == 'table' and not seen[localValue] then
      if not recurse then seen[localValue] = true end

      local m = getmetatable(localValue)
      if m and m.__name then
        write(colorize('sep', m.__name))
      end

      write(obrace)

      -- Count number of pairs
      local total = 0
      for _ in pairs(localValue) do total = total + 1 end

      local i = 0
      for k, v in pairs(localValue) do
        i = i + 1
        indent()
        if k == i then
          process(v)
        else
          if type(k) == "string" and string.find(k, "^[%a_][%a%d_]*$") then
            write(colorize("property", k))
            write(equals)
          else
            write(obracket)
            process(k)
            write(cbracket)
            write(equals)
          end
          if type(v) == "table" then
            process(v)
          else
            indent()
            process(v)
            unindent()
          end
        end
        if i < total then
          write(comma)
        else
          write(" ")
        end
        unindent()
      end
      write(cbrace)
    else
      write(colorize(typ, tostring(localValue)))
    end
  end

  process(value)
  local s = table.concat(output)
  return nocolor and strip(s) or s
end

function prettyPrint(...)
  local n = select('#', ...)
  local arguments = { ... }
  for i = 1, n do
    arguments[i] = dump(arguments[i])
  end
  print(table.concat(arguments, "\t"))
end

width = 160
-- Try to auto-detect the terminal width if possible
pcall(function()
  local fh = assert(io.popen "stty size")
  local line = fh:read "*a"
  if line then
    local w = tonumber(line:match "[0-9]+ ([0-9]+)")
    if w then width = w end
  end
  fh:close()
end)
defaultTheme = 256

loadColors()

return {
  loadColors = loadColors,
  theme = theme,
  print = print,
  prettyPrint = prettyPrint,
  dump = dump,
  color = color,
  colorize = colorize,
  stdin = stdin,
  stdout = stdout,
  stderr = stderr,
  strip = strip,
}

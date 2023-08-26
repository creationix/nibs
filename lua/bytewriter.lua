local ffi = require 'ffi'
local sizeof = ffi.sizeof
local copy = ffi.copy
local cast = ffi.cast
local ffi_string = ffi.string
local U8Arr = ffi.typeof "uint8_t[?]"
local U8Ptr = ffi.typeof "uint8_t*"
local bit = require 'bit'
local lshift = bit.lshift

---@class ByteWriter
---@field capacity integer
---@field size integer
---@field data integer[]
local ByteWriter = { __name = "ByteWriter" }
ByteWriter.__index = ByteWriter

---@param initial_capacity? integer
---@return ByteWriter
function ByteWriter.new(initial_capacity)
  initial_capacity = initial_capacity or 128
  return setmetatable({
    capacity = initial_capacity,
    size = 0,
    data = U8Arr(initial_capacity)
  }, ByteWriter)
end

---@param needed integer
function ByteWriter:ensure(needed)
  if needed <= self.capacity then return end
  repeat
    self.capacity = lshift(self.capacity, 1)
  until needed <= self.capacity
  -- print("new capacity", self.capacity)
  local new_data = U8Arr(self.capacity)
  copy(new_data, self.data, self.size)
  self.data = new_data
end

---@param str string
function ByteWriter:write_string(str)
  local len = #str
  self:ensure(self.size + len)
  copy(self.data + self.size, str, len)
  self.size = self.size + len
end

---@param bytes integer[]|ffi.cdata*
---@param len? integer
function ByteWriter:write_bytes(bytes, len)
  len = len or assert(sizeof(bytes))
  self:ensure(self.size + len)
  copy(self.data + self.size, cast(U8Ptr, bytes), len)
  self.size = self.size + len
end

function ByteWriter:to_string()
  return ffi_string(self.data, self.size)
end

function ByteWriter:to_bytes()
  local buf = U8Arr(self.size)
  copy(buf, self.data, self.size)
  return buf
end

return ByteWriter
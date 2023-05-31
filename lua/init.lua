local Nibs = require 'nibs'
local Tibs = require 'tibs'
return {
  encode = Nibs.encode,
  decode = Nibs.decode,
  get = Nibs.get,
  toTibs = Tibs.encode,
  fromTibs = Tibs.decode,
}

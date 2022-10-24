local Nibs = require 'nibs'
local Tibs = require 'tibs'
local remote = require 'remote-nibs'
return {
  encode = Nibs.encode,
  decode = Nibs.get,
  toTibs = Tibs.encode,
  fromTibs = Tibs.decode,
  remoteNibs = remote,
}

local import = _G.import or require

local Nibs = import 'nibs'
local Tibs = import 'tibs'
return {
  encode = Nibs.encode,
  decode = Nibs.decode,
  get = Nibs.get,
  toTibs = Tibs.encode,
  fromTibs = Tibs.decode,
}

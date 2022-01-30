local Decoder = require './read-nibs'
local Encoder = require './encode-nibs'
local Nibs = {}

Nibs.encode = Encoder.encode
Nibs.decode = Decoder.decode

return Nibs
import * as Nibs from './nibs.js'
import * as Tibs from './tibs.js'
import * as XXHash64 from './xxhash64.js'

export const encode = Nibs.encode
export const decode = Nibs.decode
export const optimize = Nibs.optimize
export const toMap = Nibs.toMap
export const fromTibs = Tibs.decode
export const toTibs = Tibs.encode
export const xxh64 = XXHash64.xxh64

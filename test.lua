
local pckr = require("pckr")


local a = {}
local b = {a}
local c = {a=a, b=b}
c.c = c


local dat = pckr.serialize(a, b, c)

print(inspect(dat))

local A, B, C = pckr.deserialize(dat)



print(A, B, C)


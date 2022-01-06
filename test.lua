
local pckr = require("pckr")


local A = {}
local B = {A}
local C = {a=B, b=B}
C.c = C


print(inspect(A) .. "\n" .. inspect(B) .. "\n" .. inspect(C))

print("\n\n\n")

local dat = pckr.serialize(A, B, C)


A, B, C = pckr.deserialize(dat)


print(inspect(A) .. "\n" .. inspect(B) .. "\n" .. inspect(C))



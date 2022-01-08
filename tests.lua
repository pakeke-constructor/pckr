
local pckr = require("pckr")


--[[
    https://stackoverflow.com/questions/25922437/how-can-i-deep-compare-2-lua-tables-which-may-or-may-not-have-tables-as-keys
]]
local function deep_equal(table1, table2)
    local avoid_loops = {}
    local function recurse(t1, t2)
       -- compare value types
       if type(t1) ~= type(t2) then return false end
       -- Base case: compare simple values
       if type(t1) ~= "table" then return t1 == t2 end
       -- Now, on to tables.
       -- First, let's avoid looping forever.
       if avoid_loops[t1] then return avoid_loops[t1] == t2 end
       avoid_loops[t1] = t2
       -- Copy keys from t2
       local t2keys = {}
       local t2tablekeys = {}
       for k, _ in pairs(t2) do
          if type(k) == "table" then table.insert(t2tablekeys, k) end
          t2keys[k] = true
       end

       if not recurse(getmetatable(t1), getmetatable(t2)) then
            return false
       end

       -- Let's iterate keys from t1
       for k1, v1 in pairs(t1) do
          local v2 = t2[k1]
          if type(k1) == "table" then
             -- if key is a table, we need to find an equivalent one.
             local ok = false
             for i, tk in ipairs(t2tablekeys) do
                if deep_equal(k1, tk) and recurse(v1, t2[tk]) then
                   table.remove(t2tablekeys, i)
                   t2keys[tk] = nil
                   ok = true
                   break
                end
             end
             if not ok then return false end
          else
             -- t1 has a key which t2 doesn't have, fail.
             if v2 == nil then return false end
             t2keys[k1] = nil
             if not recurse(v1, v2) then return false end
          end
       end
       -- if t2 has a key which t1 doesn't have, fail.
       if next(t2keys) then return false end
       return true
    end
    return recurse(table1, table2)
end

do
assert(not deep_equal(1, 2))
assert(deep_equal("foobar", "foobar"))
assert(deep_equal({1,2,3,4}, {1,2,3,4}))
local a = {{{}}}
a.a = a
assert(deep_equal(a, a))

local ne = {{{}}}
ne.neeee = ne
ne.abc = a
assert(deep_equal(ne, ne))
assert(not deep_equal(ne, a))
end


local function check(tab)
    local dat = pckr.serialize(tab)
    local res, e = pckr.deserialize(dat)
    if not res then
        error(e)
    end

    local r = deep_equal(tab, res)
    if not r then
        print("=============== ERROR PRINTER ===============")
        print("initial: ", inspect(tab))
        print("returned: ", inspect(res))
        error("pckr tests: CHECK FAILED")
    else
        print("\n============= PASSED ================")
        print("initial: ", inspect(tab))
        print("returned: ", inspect(res))
        print("============= PASSED ================\n")
    end
end


do
local aa = {}
local A = {}
pckr.register(A, "LLLL")
aa.A = A
aa.B = A

check(aa)
end


do
local A = {}
local B = {A}
local C = {a=B, b=B}
local D = {{{{}}}}
C.c = C

pckr.register(A, 1)
pckr.register(B, "I am the wonderful B!!!!!")

local test1 = {A,B,C,D}
local dat = pckr.serialize(test1)
local result1, err = pckr.deserialize(dat)
if not result1 then
    error(err)
end

if not deep_equal(test1, result1) then
    print(inspect(test1))
    print(inspect(result1))
    error("oh shit")
end
end



do
check(58879)
check(58880)
check(58881)
end


do
check("abcdefs;ofgLKKDDDDDDDDDDDDDDDDDDDLFKDL")
check({{{{}}}})
check({1,2,3})
end





do
    -- TODO: This test is failing:::
    local b = {b="self ref meta"}
    setmetatable(b, b)
    check(b)
end




do
    -- TODO: This test is failing:::
    local b = {b="self ref meta (try 2)"}
    setmetatable(b, {__index = b})
    check(b)
end




do
    -- This test is also failing:::
    local a = {b="ekrf"}
    local b = {b="1"}
    setmetatable(a, b)
    --[[
        I know why as well. it's in the `serialize_with_meta` function-
        before that function is called, it pushes `b` as a reference.
        When the serializer goes to serialize the metatable of b, it realizes
        that b is a reference (because it was pushed previously!!!)
        This is where the error comes from.
    ]]
    check(a)
end





print("==============================================")
print("=========== pckr: all tests passed ===========")
print("==============================================")


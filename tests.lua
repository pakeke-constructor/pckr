
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

       -- (pakeke monkeypatch.)
       if not recurse(getmetatable(t1), getmetatable(t2)) then
            return false
       end
       -- (pakeke monkeypatch END)

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


local function print_bytes(pre, dat)
    local res = dat:byte(1,1)
    for i=2, dat:len() do
        res = res .. "-" .. dat:byte(i,i)
    end
    print(pre, res)
end


local ALL_LOUD = false

local function check(tab, loud)
    local dat = pckr.serialize(tab)
    local res, e = pckr.deserialize(dat)
    if not res then
        print("ERROR IN DESERIALIZE. ")
        print("WANTED TO DESERIALIZE THIS: ", inspect(tab))
        print_bytes("DATA: ", dat)
        error(e)
    end

    local r = deep_equal(tab, res)
    if not r then
        print("=============== ERROR PRINTER ===============")
        print("initial: ", inspect(tab))
        print("returned: ", inspect(res))
        error("pckr tests: CHECK FAILED")
    elseif loud or ALL_LOUD then
        print("\n============= PASSED ================")
        print("DATA: ", dat)
        print("initial: ", inspect(tab))
        print("returned: ", inspect(res))
        print("============= PASSED ================\n")
    end
end


do
local a = {1}
check(a)
end



do
for i=1, 10 do
    check(string.rep("r", i))
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
check(test1)
end



do
check(58879)
check(58880)
check(58881)
check(-349495)
check(3409945.34893984)
check(0.0000034359)
check(999.92334958)
check(-5900069.69696239)
end



do
check("abcdefs;ofgLKKDDDDDDDDDDDDDDDDDDDLFKDL")
check({{{{}}}})
check({1,2,3})
end





do
local b = {b="self ref meta"}
setmetatable(b, b)
check(b)
end




do
local b = {b="self ref meta (try 2)"}
setmetatable(b, {__index = b})
check(b)
end




do
local a = {b="ekrf"}
local b = {b="1"}
setmetatable(a, b)
setmetatable(b, a)
check({a, b})
end


do
local a = {}
local b = {}
a.a = b
b.b = a
a.b = a
b.a = b
check({a,b})
end



do
local a = {1,2,3,4,5,6, {{{{}}}}, 2095, 2903.93094}
table.insert(a,a)
check(a)
end


do
local oop = {"z;kjdfsjild", foo = "Bar"}
local mt = {__index = oop}
pckr.register(mt, "mt_checker")
pckr.low.set_template(mt, {"a", "b", "c"})
local a = setmetatable({a=30949, b=mt, c=88800.589}, mt)
check(a)
pckr.unregister_all()
end


do
local bigdat = {{{{{{{{{}}}}}}}}}
pckr.register(bigdat, "a")
local d = pckr.serialize(bigdat)
assert(#d < 7, ".register not working") -- compresseion should take about 5 bytes
pckr.unregister_all()
local d2 = pckr.serialize(bigdat)
assert(#d2 > 14, ".unregister not working") -- compression should take more than 14 bytes
end




do
local custom_mt = {}
pckr.register(custom_mt, "custom")

pckr.low.set_custom_functions(custom_mt, function(buffer, x, meta)
    pckr.low.serializers.number(buffer, 69)
end,
function(re, meta)
    local num, er = pckr.low.pull(re)
    if er then
        return nil, er
    end
    if num == 69 then
        return setmetatable({}, meta)
    end
end)
local a = setmetatable({}, custom_mt)
check(a)
pckr.unregister_all()
end



do
pckr.register(math, "abcdef")
check({math, 1, math})
pckr.unregister_all()
end




do
local custom_mt = {"SHOULDN'T_BE_REFFED"}
pckr.register(custom_mt, "custom 2")
pckr.low.set_custom_functions(custom_mt, pckr.low.serialize_raw, pckr.low.deserialize_raw)
pckr.low.set_template(custom_mt, {"foo", "bar", "foobar", "lll", "nine"})

local a = setmetatable({
    foo = "foo";
    bar =  {{{{}}}};
    foobar = {custom_mt};
    lll = 4098450293845;
    nine = 999.39485
}, custom_mt)
check(a)
pckr.unregister_all()
end







print("==============================================")
print("=========== pckr: all tests passed ===========")
print("==============================================")



local assert = assert
local error = error

local select = select
local pairs = pairs

local getmetatable = getmetatable
local setmetatable = setmetatable

local rawget = rawget

local type = type
local concat = table.concat

local unpack = love.data.unpack
local pack = love.data.pack

local abs = math.abs
local max = math.max
local min = math.min
local floor = math.floor

local byte = string.byte
local char = string.char
local sub = string.sub

local pcall = pcall



local USMALL = "\230" -- there is another uint8 following this. 
-- This means that `usmall` can be between 0 - 58880, and only take up 2 bytes!
local MAX_USMALL = 58880
local USMALL_NUM = 230


-- local I16 = "\237" -- Don't serialize I16s, it will just waste time;
        -- we already have USMALL which covers most of the I16.

local I32 = "\234"
local I64 = "\235"

local U32 = "\236"
local U64 = "\237"

local NUMBER = "\238"

local NIL   = "\239"

local TRUE  = "\240"
local FALSE = "\215"

local STRING = "\242"
local STRING_REF_LEN = 4 -- strings must be at least X chars long 
                        -- to be counted as a reference.

local TABLE_WITH_META = "\246" -- (type_name,  table // flat-table // array )

-- These are all the possible table headers
local ARRAY   = "\247" -- (just values)
local TEMPLATE = "\248"
local TABLE   = "\249" -- (table data; must use `pairs` to serialize)

local TABLE_END = "\250" -- NULL terminator for tables.

-- TODO: do these types
local USER_TYPE = "\251" -- totally custom type for user.
-- i.e. there must be custom serialization for these objects.

local BYTEDATA  = "\252" -- (A love2d ByteData; requires special attention with .unpack)

local RESOURCE  = "\253" -- (uint ref)
local REF = "\254" -- (uint ref)

local FUTURE_REF = "\255" -- (uint ref)  (used for async serialization, NYI tho.)



local PREFIX = ">!1"





-- unique values for equality checks
local UNIQUE_TABLE_END = {}
local UNIQUE_TABLE = {}
local UNIQUE_TEMPLATE = {}






local pckr = {}



local function get_ser_funcs(type_, is_bytedata)
    local container = "string"
    if is_bytedata then
        container = is_bytedata
    end
    local format = PREFIX .. type_

    local ser = function(data)
        return pack(container, format, data)
    end

    local deser = function(data)
        local no_err, val, errstr = pcall(unpack, format, data)
        if no_err then
            return val
        else
            return nil, errstr
        end
    end

    return ser, deser
end



local serializers = {}

local deserializers = {}


local mt_to_name = {} -- metatable --> name_str
local name_to_mt = {} -- name_str --> metatable
local mt_to_template = {} -- metatable --> template


function pckr.register_type(metatable, name)
    assert(not name, "Duplicate registered type: " .. tostring(name))
    name_to_mt[name] = metatable
    mt_to_name[metatable] = name
end


function pckr.unregister_type(metatable, name)
    local mt = name_to_mt[name]
    if not mt then -- has no name
        mt = metatable
    end
    
    if name then
        name_to_mt[name] = nil
    end
    if mt then
        mt_to_name[mt] = nil

        mt_to_template[mt] = nil
    end
end


function pckr.unregister_all()
    name_to_mt = {}
    mt_to_name = {}
    mt_to_template = {}
end


function pckr.register_template(name_or_mt, template)
    -- Templates must be registered the same!
    local mt = name_or_mt
    if type(name_or_mt) == "string" then
        mt = name_to_mt[name_or_mt] -- assume `name_or_mt` is name
    end
    mt_to_template[mt] = template
end



function pckr.register_array(name_or_mt)
    -- registers the given metatable as an array type
    local mt = name_or_mt
    if type(name_or_mt) == "string" then 
        mt = name_to_mt[name_or_mt] -- assume `name_or_mt` is name
        mt_to_name[mt] = name_or_mt
    else
        error("pckr.register_array takes a string")
    end
end




local function add_reference(buffer, x)
    local refs = buffer.refs
    local new_count = refs.count + 1
    refs[x] = new_count
    refs.count = new_count
end














--[[

Serializers:

]]


local function push(buffer, x)
    -- pushes `x` onto the buffer
    local newlen = buffer.len + 1
    buffer[newlen] = x
    buffer.len = newlen
end


local function push_ref(buffer, ref_num)
    push(buffer, REF)
    serializers.number(buffer, ref_num)
end


local function serialize_raw(buffer, x)
    push(buffer, TABLE)
    for k,v in pairs(x) do
        serializers[type(k)](buffer, k)
        serializers[type(v)](buffer, v)
    end
    push(buffer, TABLE_END)
end


local function push_array_to_buffer(buffer, x)
    -- `x` is array
    push(buffer, ARRAY)
    for i=1, #x do
        serializers[type(x[i])](buffer, x[i])
    end
    -- TABLE_END shouldn't be pushed here.
end



--[[     anatomy:

`ARRAY`  --> denotes a list of values. <val1, val2, ...>
`TEMPLATE`  --> denotes a templates type.  <typename, val1, val2, val3, ...>
`TABLE` --> denotes a key-val relation:  <key1, val1, key2, val2, ...>


possible types:

`TABLE_WITH_META` <meta> `ARRAY` <arr_data> `TABLE` <table_data> TABLE_END
`TABLE_WITH_META` <meta> `ARRAY` <arr_data> `TEMPLATE` <table_data> TABLE_END
`TABLE_WITH_META` <meta> `TABLE` <data> TABLE_END
`TABLE_WITH_META` <meta> `TEMPLATE` <data> TABLE_END
note that template can't have regular keys afterwards

]]

local function serialize_mt_header(buffer, meta)
    assert(type(meta) == "table", "`meta` not a table..?")
    local name = mt_to_name[meta]
    if name then
        serializers.string(buffer, name)
    else
        serializers.table(buffer, meta)
    end

end


local function serialize_with_meta(buffer, x, meta)
    push(buffer, TABLE_WITH_META)

    serialize_mt_header(buffer, meta) -- serializes metatable OR string name

    if rawget(x, 1) then
        push_array_to_buffer(buffer, x)
    end

    if mt_to_template[meta] then
        push(buffer, TEMPLATE)
        local template = mt_to_template[meta]
        for i=1, #template do
            local k = template[i]
            local val = x[k]
            serializers[type(val)](buffer, val)
        end
        push(buffer, TABLE_END)
    else
        -- gonna have to serialize normally, oh well
        serialize_raw(buffer, x)
    end
end



function serializers.table(buffer, x)
    if buffer.refs[x] then
        push_ref(buffer, buffer.refs[x])
    else
        add_reference(buffer, x)
        local meta = getmetatable(x)
        if meta then
            serialize_with_meta(buffer, x, meta)
        else
            serialize_raw(buffer, x)
        end
    end
end


serializers["nil"] = function(buffer, _)
    push(buffer, NIL)
end


-- Number serialization:
local sUSMALL, dUSMALL = get_ser_funcs("I2")
local sU32, dU32 = get_ser_funcs("I4")
local sU64, dU64 = get_ser_funcs("I8")
local sI32, dI32 = get_ser_funcs("i4")
local sI64, dI64 = get_ser_funcs("i8")
local sN, dN = get_ser_funcs("n")


function serializers.number(buffer, x)
    if floor(x) == x then
        -- then is integer
        if x > 0 then
            -- serialize unsigned
            if x < MAX_USMALL then
                push(buffer, sUSMALL(x))
            elseif x < (2^32 - 1) then
                push(buffer, U32)
                push(buffer, sU32(x))
            else -- x is U64
                push(buffer, U64)
                push(buffer, sU64(x))
            end
        else
            -- serialize signed
            local mag = abs(x)
            if mag < (2 ^ 31 - 2) then -- 32 bit signed num
                push(buffer, I32)
                push(buffer, sI32(x))
            else
                push(buffer, I64) -- else its 64 bit.
                push(buffer, sI64(x))
            end
        end
    else
        push(buffer, NUMBER)
        push(buffer, sN(x))
    end
end


function serializers.string(buffer, x)
    if buffer.refs[x] then
        push_ref(buffer, buffer.refs[x])
    else
        push(buffer, STRING)
        push(buffer, x)
        push(buffer, "\0") -- remember to push null terminator!
        -- TODO: Is this null terminator needed? Do testing
        if x:len() >= STRING_REF_LEN then
            add_reference(buffer, x)
        end
    end
end













--[[

deserializers

]]


local function popn(reader, n)
    local i = reader.index
    local data = reader.data
    reader.index = i + n
    if data:len() >= i + n then
        return reader.data:sub(i, i + n)
    else
        return nil, "data string too short"
    end
end



local function pull(reader)
    local i = reader.index
    local ccode = byte(reader.data, i)
    local chr = sub(reader.data, i, i)
    
    --print("pull:  ",chr:byte(1,1)) -- TODO: remove this ghost comment
    
    if ccode <= USMALL_NUM then
        deserializers[USMALL](reader)
    end
    local chr = sub(reader.data, i, i)
    local fn = deserializers[chr]
    if not fn then
        return nil, "Serialization char not found: " .. tostring(chr:byte(1,1))
    end
    reader.index = i + 1
    local val, err = fn(reader)
    if err then
        return nil, err
    end
    return val
end


local function pull_ref(reader, x)
    -- adds a new reference to the reader.
    local refs = reader.refs
    refs.count = refs.count + 1
    refs[refs.count] = x
end

local function get_ref(reader, index)
    return reader.refs[index]
end



local function make_number_deserializer(deser_func, n_bytes)
    return function(re)
        local data, er1 = popn(re, n_bytes)
        if not data then
            return nil, er1
        end

        local num, er2 = deser_func(data)
        if not num then
            return nil, er2
        end
        return num
    end
end



deserializers[USMALL] = make_number_deserializer(dUSMALL, 2)

deserializers[U32] = make_number_deserializer(dU32, 4)
deserializers[I32] = make_number_deserializer(dI32, 4)

deserializers[I64] = make_number_deserializer(dI64, 8)
deserializers[U64] = make_number_deserializer(dU64, 8)

local size_NUMBER = love.data.getPackedSize(PREFIX .. "n") -- i forgot size :P
deserializers[NUMBER] = make_number_deserializer(dN, size_NUMBER)


deserializers[NIL] = function(_)
    return nil
end

deserializers[TRUE] = function(_)
    return true
end

deserializers[FALSE] = function(_)
    return false
end


local format_STRING = PREFIX .. "z"
deserializers[STRING] = function(re)
    -- null terminated string
    local no_err, res, i = pcall(unpack, format_STRING, re.data, re.index)
    if no_err then
        if STRING_REF_LEN >= res:len() then
            -- then we put as a ref
            pull_ref(re, res)
        end
        re.index = i
        return res
    else
        return nil, res -- `res` is error string here.
    end
end




local function read_meta_header(re)
    local val, err = pull(re)
    if err then
        return nil, tostring(err)
    end

    local meta
    if type(val) == "string" then
        meta = name_to_mt[val]
    else -- it's got to be table
        meta = val
    end
    if type(meta) ~= "table" then
        return nil, "after TABLE_WITH_META, there needs to be a string or table."
    end
    return meta
end


deserializers[TABLE_WITH_META] = function(re)
    --[[
        format is like this:
        TABLE_WITH_META (metatable or string)
        FLAT_TABLE (this means there is a template)
        ARRAY (this means we treat as array)        
    ]]
    local meta, err = read_meta_header(re)
    if not meta then
        return nil, err
    end

    local tabl = pull(re)
    if type(tabl) ~= "table" then
        return nil, "TABLE_WITH_META requires the following sig: [str or metatab], [table] "
    end
    return setmetatable(tabl, meta)
end



deserializers[ARRAY] = function(re, mt_or_nil)
    -- Remember for an array: 
    -- TABLE, TEMPLATE, or TABLE_END could all follow!
    -- We must account for that; `ARRAY` should automatically pull these extra
    -- headers.
    local tabl = {}
    local tinsert = table.insert

    while true do
        local x, err = pull(re)
        if err then
            return nil, err
        end
        if x == UNIQUE_TABLE then
            return deserializers[TABLE](re, tabl, mt_or_nil)
        end
        if x == UNIQUE_TEMPLATE then
            return deserializers[TEMPLATE](re, tabl, mt_or_nil)
            -- don't worry about `mt_or_nil` being nil, `TEMPLATE` deserializer will handle this
        end
        if x == UNIQUE_TABLE_END then
            return tabl
        end
        tinsert(tabl, x)
    end
end



deserializers[TABLE] = function(re, tab_or_nil)
    local tab = tab_or_nil or {}

    while true do
        local key, er1 = pull(re)
        if er1 or (key == nil) then
            return nil, er1
        end

        if key == UNIQUE_TABLE_END then
            return tab
        else
            local val, er2 = pull(re)
            if er2 then
                return nil, er2
            end
            tab[key] = val
        end
    end
end



deserializers[TEMPLATE] = function(re, meta, tabl_or_nil)
    if not (meta) then
        return nil, "deserializers[TEMPLATE] didn't pass in meta!"
    end

    local templ = mt_to_template[meta]
    if not (templ) then
        return nil, "deserializers[TEMPLATE]: No template for metatable type!"
    end

    local tabl = tabl_or_nil or {}
    local i = 1
    local len = #templ

    while i <= len do
        local x, err = pull(re)
        if err then
            return nil, err
        end
        local key = templ[i]
        tabl[key] = x
        i = i + 1
    end

    local x, err = pull(re)
    if x ~= UNIQUE_TABLE_END then
        -- we don't *really* need this here, but it's safer to check.
        return nil, err
    end

    return tabl
end



deserializers[TABLE_END] = function(_)
    return UNIQUE_TABLE_END
end



deserializers[REF] = function(re)
    local index = pull(re)
    if type(index) ~= "number" then
        return nil, "Reference not a number"
    end
    local val = get_ref(re, index)
    if not val then
        return nil, "Non existant reference: " .. tostring(index)
    end
    return val
end






local function newbuffer()
    local buffer = {
        len = 0;
        refs = {count = 0} -- count = the number of references.
    }
    return buffer
end


local function newreader(data)
    return {
        results = {};

        refs = {count = 0}; -- [ref_num] --> object
        
        data = data;
        index = 1
    }
end


function pckr.serialize(...)
    local buffer = newbuffer()

    local len = select("#", ...)
    for i=1, len do
        local x = select(i, ...)
        serializers[type(x)](buffer, x)
    end
    return concat(buffer)
end



function pckr.deserialize(data)
    local reader = newreader(data)

    local DEBUG_I = 1
    while data:len() >= reader.index do

        DEBUG_I = DEBUG_I + 1
        if DEBUG_I > 11 then
            return
        end

        local val = pull(reader)
        table.insert(reader.results, val)
    end

    -- TODO: ISSUE HERE!
    -- If theres a `nil` value in the middle of the array,
    -- unpack doesn't unpack the whole thing.
    -- (There could be an extra arg to unpack though, so take a look)
    return unpack(reader.results)
end



--[[

TODO FOR FUTURE

function pckr.serialize_async()
end


function pckr.deserialize_async()
end

]]


return pckr

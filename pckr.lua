
local assert = assert
local error = error

local select = select
local pairs = pairs

local getmetatable = getmetatable
local setmetatable = setmetatable

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

local ARRAY   = "\247" -- (just values)
local FLAT_TABLE = "\258"
local TABLE   = "\249" -- (table data; must use `pairs` to serialize)
local TABLE_END = "\250" -- NULL terminator for tables.


local USER_TYPE = "\251" -- totally custom type for user.
-- i.e. there must be custom serialization for these objects.

local BYTEDATA  = "\252" -- (A love2d ByteData; requires special attention with .unpack)

local RESOURCE  = "\253" -- (uint ref)
local REF = "\254" -- (uint ref)

local FUTURE_REF = "\255" -- (uint ref)  (used for async serialization, NYI tho.)



local PREFIX = ">!1"



local pckr = {}



local function get_ser_funcs(type, is_bytedata)
    local container = "string"
    if is_bytedata then
        container = is_bytedata
    end
    local format = PREFIX .. type

    local ser = function(data)
        return pack(container, format, data)
    end

    local deser = function(data)
        return pcall(unpack, format, data)
    end

    return ser, deser
end



local serializers = {}

local deserializers = {}


local mt_to_name = {} -- metatable --> name_str
local name_to_mt = {} -- name_str --> metatable
local mt_to_template = {} -- metatable --> template
local mt_to_arraybool = {} -- metatable --> is array? (boolean)


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
        mt_to_arraybool[mt] = nil
    end
end


function pckr.unregister_all()
    name_to_mt = {}
    mt_to_name = {}
    mt_to_template = {}
    mt_to_arraybool = {}
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
        serializers[type(k)](k)
        serializers[type(v)](v)
    end
    push(buffer, TABLE_END)
end


local function push_array_to_buffer(buffer, x)
    -- `x` is array
    push(buffer, ARRAY)
    for i=1, #x do
        serializers[type(x[i])](x[i])
    end
    -- TABLE_END shouldn't be pushed here.
end



--[[     anatomy:

TABLE_WITH_META type_str OR metatable  <TABLE_DATA>

TABLE
-- Make sure to push ref before you start!
<key, value> <key value> ...  TABLE_END

ARRAY 
<value> <value> <value> ...  TABLE_END

FLAT_TABLE
<type string>  <value> <value> ... TABLE_END
]]
local function serialize_with_meta(buffer, x, meta)
    assert(type(meta) == "table", "`meta` not a table..?")
    local name = mt_to_name[meta]
    
    push(buffer, TABLE_WITH_META)
    if name then
        serializers.string(buffer, name)
    else
        serializers.table(buffer, meta)
    end

    if mt_to_template[meta] then
        push(buffer, FLAT_TABLE)
        local template = mt_to_template[meta]
        for i=1, #template do
            local k = template[i]
            local val = x[k]
            serializers[type(val)](val)
        end
        push(buffer, TABLE_END)
    elseif mt_to_arraybool[meta] then
        -- then it's just an array- no template
        push_array_to_buffer(buffer, x)
        push(buffer, TABLE_END)
    else
        -- gonna have to serialize normally, oh well
        serialize_raw(x)
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
            serialize_raw(x)
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
    reader.index = i + n
    if reader:len() >= i + n then
        return reader.data:sub(i, i + n)
    else
        return nil, "data string too short"
    end
end



local function pull(reader)
    local i = reader.index
    local ccode = byte(reader.data, i)
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


deserializers[NIL] = function(re)
    return nil
end

deserializers[TRUE] = function(re)
    return true
end

deserializers[FALSE] = function(re)
    return false
end


local format_STRING = PREFIX .. "z"
deserializers[STRING] = function(re)
    -- null terminated string
    local res, i = pcall(unpack, format_STRING, re.data, re.index)
    if res then
        if STRING_REF_LEN >= res:len() then
            -- then we put as a ref
            pull_ref(re, res)
        end
        re.index = i
        return res
    else
        return nil, i -- `i` is error string here.
    end
end




deserializers[TABLE_WITH_META] = function(re)
    --[[
        format is like this:
        TABLE_WITH_META (metatable or string)
        FLAT_TABLE (this means there is a template)
        ARRAY (this means we treat as array)        
    ]]
    local val, err = pull(re)
    if err then
        return nil, err
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

    local tabl = pull(re)
    if type(tabl) ~= "table" then
        return nil, "TABLE_WITH_META requires the following sig: [str or metatab], [table] "
    end
    return setmetatable(tabl, meta)
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
        i = 1
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

    while data:len() >= data.index do
        local val = pull(reader)
        table.insert(reader.results, val)
    end

    -- TODO: ISSUE HERE!
    -- If theres a `nil` value in the middle of the array,
    -- unpack doesn't unpack the whole thing.
    -- (There could be an extra arg to unpack though, so take a look)
    return unpack(reader.results)
end




function pckr.serialize_async()
    -- returns `buffer` object
end


function pckr.deserialize_async()

end




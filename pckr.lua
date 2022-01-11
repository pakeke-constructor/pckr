
local assert = assert
local error = error

local select = select
local pairs = pairs

local getmetatable = getmetatable
local setmetatable = setmetatable

local rawget = rawget

local type = type
local concat = table.concat

local table_unpack = unpack
local unpack = love.data.unpack
local pack = love.data.pack

local abs = math.abs
local floor = math.floor

local byte = string.byte
local len = string.len
local sub = string.sub

local pcall = pcall




local USMALL = 230 -- there is another uint8 following this. 
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
local FALSE = "\241"

local STRING = "\242"
local STRING_REF_LEN = 4 -- strings must be at least X chars long 
                        -- to be counted as a reference.

local TABLE_WITH_META = "\244" -- ( table // flat-table // array, metatable )

-- These are all the possible table headers
local ARRAY   = "\246" -- (just values)
local ARRAY_END = "\247"

local TEMPLATE = "\248"
local TABLE   = "\249" -- (table data; must use `pairs` to serialize)

local TABLE_END = "\250" -- NULL terminator for tables.

-- TODO: do these types
local USER_TYPE = "\251" -- totally custom type for user.
-- i.e. there must be custom serialization for these objects.

local BYTEDATA  = "\252" -- (A love2d ByteData; requires special attention with .unpack)

local RESOURCE  = "\253" -- (ANY_TYPE alias_ref)
local REF = "\254" -- (uint ref)

local FUTURE_REF = "\255" -- (uint ref)  (used for async serialization, NYI tho.)



local PREFIX = ">!1"



-- unique values for equality checks
local UNIQUE_TABLE_END = {}
local UNIQUE_ARRAY_END = {}

-- unique key for ref hashers.
local COUNT = {"reference_counter"}







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





local alias_to_resource = {}
local resource_to_alias = {}

local mt_to_template = {} -- metatable --> template


local mt_to_custom_serial = {} -- [mt] --> function(buffer, x) -- custom ser.
local mt_to_custom_deserial = {} -- [mt] --> function(reader, x) -- custom ser






function pckr.register(resource, alias)
    assert(alias, "pckr.register(resource, alias): Not given an alias")
    if type(resource) == "number" or type(resource) == "nil" or
                                     type(resource) == "boolean" or
                                     type(resource) == "string" then
        error("pckr.register(resource, alias): You cannot register bools, numbers, string, or nil.")
    end
    alias_to_resource[alias] = resource
    resource_to_alias[resource] = alias
end



local function unregister_low(meta)
    mt_to_template[meta] = nil
    mt_to_custom_deserial[meta] = nil
    mt_to_custom_serial[meta] = nil
end


local function get_res_alias(res_or_alias)
    -- gets resource, alias  tuple with either res or alias.
    -- returns nil if neither are registered
    local res, alias
    if resource_to_alias[res_or_alias] then
        res = res_or_alias
        alias = resource_to_alias[res_or_alias]
    elseif alias_to_resource[res_or_alias] then
        alias = res_or_alias
        res = alias_to_resource
    end
    return res, alias
end


function pckr.unregister(res_or_alias)
    if not res_or_alias then
        error("pckr.unregister expects either a name, resource, or metatable")
    end
    local res, alias = get_res_alias(res_or_alias)
    if alias_to_resource[alias] then
        alias_to_resource[alias] = nil
        resource_to_alias[res] = nil
        unregister_low(res)
        return true
    end
    return false
end



function pckr.unregister_all()
    mt_to_template = {}
    alias_to_resource = {}
    resource_to_alias = {}

    mt_to_custom_serial = {}
    mt_to_custom_deserial = {}
end


-- low level:
pckr.low = {}

function pckr.low.set_template(res_or_alias, templ)
    assert(#templ > 0, "pckr: Incorrect template usage. See readme.md")
    local res, _ = get_res_alias(res_or_alias)
    assert(res, "pckr.low.set_template(meta, templ) must be used on a registered type!")
    mt_to_template[res] = templ
end


function pckr.low.set_custom_functions(res_or_alias, ser, deser)
    if not res_or_alias then
        error("pckr.low.set_custom_functions: incorrect function signature")
    end
    assert(ser and deser, "pckr.low.set_custom_functions(meta, ser, deser) requires functions for serializing AND deserializing")
    local res, _ = get_res_alias(res_or_alias)
    if res then
        mt_to_custom_serial[res] = ser
        mt_to_custom_deserial[res] = deser
    else
        error("pckr.low.set_custom_functions(meta, ser, deser) must be used on a registered type!")
    end
end












local serializers = {}

local deserializers = {}





--[[

Serializers:

]]

local function add_ref(buffer, x)
    local refs = buffer.refs
    local new_count = refs[COUNT] + 1
    refs[x] = new_count
    refs[COUNT] = new_count
end




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



local function try_push_resource(buffer, res)
    local alias = resource_to_alias[res]
    if alias then
        push(buffer, RESOURCE)
        print("PUSHING RESOURCE OF ALIAS TYPE:: ", type(alias))
        print("BUFFER.REFS:: ", inspect(buffer.refs))
        serializers[type(alias)](buffer, alias)
        return true
    end
    return false
end


local function force_push_resource(buffer, x)
    if not try_push_resource(buffer, x) then
        error("Attempt to serialize illegal type: " .. type(x))
    end
end

--[[
=================
    set a default serialization function for unknown types.
=================
]]
setmetatable(serializers, {__index = function() return force_push_resource end})





local function push_array_to_buffer(buffer, x)
    push(buffer, ARRAY)
    local arr_len = #x
    for i=1, arr_len do
        serializers[type(x[i])](buffer, x[i])
    end
    push(buffer, ARRAY_END)
    return arr_len
end

local function should_skip(arr_len, key)
    -- returns whether this key should be skipped because it's in the array
    return arr_len and type(key) == "number" and 
                floor(key) == key and key <= arr_len and key > 0
end


local function serialize_raw(buffer, x)
    local arr_len
    if rawget(x, 1) then
        arr_len = push_array_to_buffer(buffer, x)
    end

    push(buffer, TABLE)
    for k,v in pairs(x) do
        if not should_skip(arr_len, k) then
            serializers[type(k)](buffer, k)
            serializers[type(v)](buffer, v)
        end
    end
    push(buffer, TABLE_END)
end



--[[     anatomy:

`ARRAY`  --> denotes a list of values. <val1, val2, ...>
`TEMPLATE`  --> denotes a templates type.  <typename, val1, val2, val3, ...>
`TABLE` --> denotes a key-val relation:  <key1, val1, key2, val2, ...>


possible types:

`TABLE_WITH_META`  (`ARRAY` <arr_data> `TABLE` <table_data> TABLE_END)    <meta>
`TABLE_WITH_META`  (`ARRAY` <arr_data> `TEMPLATE` <table_data> TABLE_END)   <meta>
`TABLE_WITH_META`  (`TABLE` <data> TABLE_END)    <meta>
`TABLE_WITH_META`  (`TEMPLATE` <data> TABLE_END)   <meta>
note that template can't have regular keys afterwards   

]]

local function push_template(buffer, x, meta, arr_len)
    push(buffer, TABLE)
    push(buffer, TABLE_END)
    -- gotta push this to inform deserializer that the metatable isn't

    serializers.table(buffer, meta)

    push(buffer, TEMPLATE)
    local template = mt_to_template[meta]
    for i=1, #template do
        local k = template[i]
        if not should_skip(arr_len, k) then
            local val = x[k]
            serializers[type(val)](buffer, val)
        end
    end
    push(buffer, TABLE_END)
end




local function serialize_user_type(buffer, x, meta)
    push(buffer, USER_TYPE)
    local fn = mt_to_custom_serial[meta]
    try_push_resource(buffer, meta) -- this will always succeed,
    -- due to the nature of low level registering.
    -- mt_to_custom_serial[meta] will ALWAYS be nil if `meta` isn't a custom
    -- resource-- (see low.set_custom_functions)
    fn(buffer, x, meta)
end


local function serialize_with_meta(buffer, x, meta)
    push(buffer, TABLE_WITH_META)

    if mt_to_template[meta] then
        local arr_len = nil
        if rawget(x, 1) then
            arr_len = push_array_to_buffer(buffer, x)
        end
        push_template(buffer, x, meta, arr_len)
    else
        -- gonna have to serialize normally, oh well
        serialize_raw(buffer, x)
        serializers.table(buffer, meta)
    end
end



function serializers.table(buffer, x)
    if resource_to_alias[x] and try_push_resource(buffer, x) then
        -- (This first condition before the `and` is just a shortcut check, saves us a stack frame)
        return -- It's a resource- hooray
    elseif buffer.refs[x] then
        push_ref(buffer, buffer.refs[x])
    else
        add_ref(buffer, x)
        local meta = getmetatable(x)
        if meta then
            if mt_to_custom_serial[meta] then
                serialize_user_type(buffer, x, meta)
            else
                serialize_with_meta(buffer, x, meta)
            end
        else
            serialize_raw(buffer, x)
        end
    end
end


serializers["nil"] = function(buffer, _)
    push(buffer, NIL)
end

serializers.boolean = function(buffer, x)
    if x then
        push(buffer, TRUE)
    else
        push(buffer, FALSE)
    end
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


--[[
    STRING
    <string len>
    <..... string data ...........>
]]
function serializers.string(buffer, x)
    if buffer.refs[x] then
        push_ref(buffer, buffer.refs[x])
    else
        push(buffer, STRING)
        local slen = len(x)
        serializers.number(buffer, slen)
        push(buffer, x)

        if slen >= STRING_REF_LEN then
            add_ref(buffer, x)
        end
    end
end













--[[

deserializers

]]


local function popn(reader, n)
    local i = reader.index
    local data = reader.data
    reader.index = i + n -- `reader.index` is the index of the NEXT byte to be read.
    -- i + n - 1 is the index of the most recent byte read.
    if len(data) >= (i + n - 1) then
        return reader.data:sub(i, i + n - 1)
    else
        return nil, "popn(reader, n): data string too short"
    end
end


local function peek(reader)
    local i = reader.index
    return sub(reader.data, i,i)
end



local function pull(reader)
    local i = reader.index
    local ccode = byte(reader.data, i)
    if not ccode then
        return nil, "pull(re) ran out of data; (serialization data too short of malformed)"
    end
    if ccode <= USMALL_NUM then
        return deserializers[USMALL](reader)
    end

    local chr = sub(reader.data, i, i)
    local fn = deserializers[chr]
    if not fn then
        return nil, "pull(re): Serialization char not found: " .. tostring(chr:byte(1,1))
    end
    reader.index = i + 1
    local val, err = fn(reader)
    if err then
        return nil, err
    end
    
    return val
end


local function pull_ref(reader, x)
    print("PULL REFERENCE:", inspect(x))
    -- adds a new reference to the reader.
    local refs = reader.refs
    refs[COUNT] = refs[COUNT] + 1
    refs[refs[COUNT]] = x
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


deserializers[STRING] = function(re)
    local string_len, err = pull(re)
    if err then
        return nil, "deserializers[STRING] - " .. err
    end
    
    local i = re.index
    local end_i = i + string_len - 1

    if len(re.data) >= (end_i) then
        -- then we OK
        local res = sub(re.data, i, end_i)
        if len(res) >= STRING_REF_LEN then
            -- then we put as a ref
            pull_ref(re, res)
        end
        re.index = end_i + 1
        return res
    else
        return nil, "deserializers[STRING]: recieved data does not have enough space to account for this string size: " .. tostring(string_len)
    end
end





deserializers[TABLE_WITH_META] = function(re)
    --[[
        format is like this:
        TABLE_WITH_META
        TABLE / ARRAY (...)
         <<metatable>>
        TEMPLATE - optional

        The template must be after the metatable, else pckr won't know
        what the template is!
    ]]
    local tabl, err = pull(re)
    if err then
        return nil, "deserializers[TABLE_WITH_META] - " .. err
    end
    if type(tabl) ~= "table"then
        return nil, "TABLE_WITH_META requires the signature: [tabl],[metatab]. `tabl` was of type: " .. type(tabl)
    end

    local meta, er2 = pull(re)
    if er2 then
        return nil, "deserializers[TABLE_WITH_META] - " .. er2
    end
    if type(meta) ~= "table"then
        return nil, "TABLE_WITH_META requires the signature: [tabl],[metatab]. `metatab` was of type: " .. type(meta)
    end

    if peek(re) == TEMPLATE then
        local er3
        re.index = re.index + 1
        tabl, er3 = deserializers[TEMPLATE](re, tabl, meta)
        if er3 then
            return nil, er3
        end
    end

    return setmetatable(tabl, meta)
end




local ALLOWED_TOKENS_AFTER_ARRAY = {
    [TABLE] = true;
    [TEMPLATE] = true;
}

deserializers[ARRAY] = function(re, mt_or_nil)
    -- Remember for an array: 
    -- TABLE, TEMPLATE, or TABLE_END could all follow!
    -- We must account for that; `ARRAY` should automatically pull these extra
    -- headers.
    local tabl = {}
    pull_ref(re, tabl)
    local tinsert = table.insert

    while true do
        local x, err = pull(re)
        if err then
            return nil, "deserializers[ARRAY] - " .. err
        end
        if x == UNIQUE_ARRAY_END then
            local key, er = popn(re, 1)
            if er then
                return nil, "deserializers[ARRAY]: error in popn: " .. er
            end
            if not ALLOWED_TOKENS_AFTER_ARRAY[key] then
                return nil, "deserializers[ARRAY] - malformed token after ARRAY_END: \\" .. tostring(key:byte(1,1))
            end

            return deserializers[key](re, tabl, mt_or_nil)
        end
        tinsert(tabl, x)
    end
end



deserializers[TABLE] = function(re, tabl_or_nil)
    local tabl
    if tabl_or_nil then
        tabl = tabl_or_nil
    else
        tabl = {}
        pull_ref(re, tabl)
    end

    while true do
        local key, er1 = pull(re)
        if er1 or (key == nil) then
            return nil, er1
        end

        if key == UNIQUE_TABLE_END then
            return tabl
        else
            local val, er2 = pull(re)
            if er2 then
                return nil, er2
            end
            tabl[key] = val
        end
    end
end



deserializers[TEMPLATE] = function(re, tabl_or_nil, meta)
    if not (meta) then
        return nil, "deserializers[TEMPLATE](re, meta, tab_or_nil) didn't pass in meta!"
    end

    local templ = mt_to_template[meta]
    if not (templ) then
        return nil, "deserializers[TEMPLATE]: No template for metatable type! (make sure it is registered)"
    end

    local tabl
    if tabl_or_nil then
        tabl = tabl_or_nil
    else
        tabl = {}
        pull_ref(re, tabl)
    end
    
    local i = 1
    local tlen = #templ

    while i <= tlen do
        local x, err = pull(re)
        if err then
            return nil, "deserializers[TEMPLATE]: " .. err
        end
        local key = templ[i]
        tabl[key] = x
        i = i + 1
    end

    local x, err = pull(re)
    if x ~= UNIQUE_TABLE_END then
        -- we don't *really* need this here, but it's safer to check.
        return nil, "deserializers[TEMPLATE]: " .. err
    end

    return tabl
end


deserializers[ARRAY_END] = function(_)
    return UNIQUE_ARRAY_END
end

deserializers[TABLE_END] = function(_)
    return UNIQUE_TABLE_END
end



deserializers[REF] = function(re)
    local index, er = pull(re)
    if er then
        return nil, "deserializers[REF] error - " .. er
    end
    if type(index) ~= "number" then
        return nil, "deserializers[REF] - Reference not a number"
    end
    local val = get_ref(re, index)
    if not val then
        return nil, "deserializers[REF] - Non existant reference: " .. tostring(index)
    end
    return val
end




deserializers[RESOURCE] = function(re)
    local alias, er = pull(re)
    if er then
        return nil, "deserializers[RESOURCE] - " .. er
    end
    local val = alias_to_resource[alias]
    if not val then
        return nil, "deserializers[RESOURCE] - unknown resource alias: " .. tostring(alias)
    end
    return val
end



deserializers[USER_TYPE] = function(re)
    local meta, er1 = pull(re)
    if er1 then
        return nil, "deserializers[USER_TYPE] error in first pull - " .. er1
    end
    if type(meta) ~= "table" then
        return nil, "deserializers[USER_TYPE] - incorrect data signature. Expected [metatab], [<user bytes>], but [metatab] was type: " .. type(meta)
    end

    local fn = mt_to_custom_deserial[meta]
    if not fn then
        return nil, "deserializers[USER_TYPE] - custom USER_TYPE not registered: " .. tostring(meta) .. ". Did you make sure to set serialization functions and register it?"
    end

    return fn(re, meta)
end



--[[
    planning for custom raw table serialization:

    - Needs to ser with template
    - Needs to ser with array
    - Needs to ser with table
    - doesn't care about meta!!!!
]]

local function low_serialize_shortcut(buffer, x)
    if resource_to_alias[x] then
        push(buffer, RESOURCE)
        local alias = resource_to_alias[x]
        serializers[type(alias)](buffer, alias)
        return true
    elseif buffer.refs[x] then
        push_ref(buffer, buffer.refs[x])
        return true
    end
    return false
end

pckr.low.serialize_raw = function(buffer, x, meta)
    if mt_to_template[meta] then
        local arr_len
        if rawget(x, 1) then
            arr_len = push_array_to_buffer(buffer, x)
        end
        push(buffer, TEMPLATE)
        local template = mt_to_template[meta]
        for i=1, #template do
            local k = template[i]
            if not should_skip(arr_len, k) then
                local val = x[k]
                serializers[type(val)](buffer, val)
            end
        end
        push(buffer, TABLE_END)
    else
        serialize_raw(buffer, x)
    end
end

pckr.low.deserialize_raw = function(reader, meta)
    local token = popn(reader, 1)
    local ret, er
    if token == ARRAY then
        ret, er = deserializers[ARRAY](reader, meta)
    elseif token == TEMPLATE then
        ret, er = deserializers[TEMPLATE](reader, nil, meta)
    elseif token == TABLE then
        ret, er = deserializers[TABLE](reader)
    else
        return nil, "pckr.low.deserialize_raw: Malformed data; expected to start data with ARRAY, TABLE, or TEMPLATE token."
    end

    if er then
        return nil, er
    else
        setmetatable(ret, meta)
    end
    return ret
end

pckr.low.push = push
pckr.low.pull = pull

pckr.low.push_ref = push_ref
pckr.low.add_ref = add_ref

pckr.low.get_ref = get_ref
pckr.low.pull_ref = pull_ref


pckr.low.I32 = "\234"
pckr.low.I64 = "\235"
pckr.low.U32 = "\236"
pckr.low.U64 = "\237"
pckr.low.NUMBER = "\238"
pckr.low.NIL   = "\239"
pckr.low.TRUE  = "\240"
pckr.low.FALSE = "\241"
pckr.low.STRING = "\242"
pckr.low.STRING_REF_LEN = 4
pckr.low.TABLE_WITH_META = "\244" -- ( table // flat-table // array, metatable )
pckr.low.ARRAY   = "\246" -- (just values)
pckr.low.ARRAY_END = "\247"
pckr.low.TEMPLATE = "\248"
pckr.low.TABLE   = "\249" -- (table data; must use `pairs` to serialize)
pckr.low.TABLE_END = "\250" -- NULL terminator for tables.
pckr.low.USER_TYPE = "\251" -- totally custom type for user.
pckr.low.BYTEDATA  = "\252" -- (A love2d ByteData; requires special attention with .unpack)
pckr.low.RESOURCE  = "\253" -- (ANY_TYPE alias_ref)
pckr.low.REF = "\254" -- (uint ref)
pckr.low.FUTURE_REF = "\255" -- (uint ref)  (used for async serialization, NYI tho.)

pckr.low.serializers = serializers
pckr.low.deserializers = deserializers


local function newbuffer()
    local buffer = {
        len = 0;
        refs = {[COUNT] = 0} -- count = the number of references.
    }
    return buffer
end


local function newreader(data)
    return {
        results = {};

        refs = {[COUNT] = 0}; -- [ref_num] --> object
        
        data = data;
        index = 1
    }
end


function pckr.serialize(...)
    local buffer = newbuffer()

    local arglen = select("#", ...)
    for i=1, arglen do
        local x = select(i, ...)
        serializers[type(x)](buffer, x)
    end
    return concat(buffer)
end



function pckr.deserialize(data)
    local reader = newreader(data)

    while data:len() >= reader.index do
        local val, err = pull(reader)
        if err then
            return nil, err
        end
        table.insert(reader.results, val)
    end

    -- TODO: ISSUE HERE!
    -- If theres a `nil` value in the middle of the array,
    -- unpack doesn't unpack the whole thing.
    -- (There could be an extra arg to unpack though, so take a look)
    return table_unpack(reader.results)
end



--[[  TODO FOR FUTURE

function pckr.serialize_async()
end

function pckr.deserialize_async()
end
]]


return pckr

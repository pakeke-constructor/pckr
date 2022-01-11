
# pckr
`pckr` is a serialization library for love2d.
It is very good at serializing large data.

I'm also aiming for it to be a lot more extensible than other custom serializers.



# usage:

```lua

-- registers a resource (same as binser, but you can use any type as alias.)
pckr.register(resource, alias)

pckr.unregister(resource) -- unregisters resource

pckr.unregister_all() -- unregisters all resources



-- Simple deserialization and serialization
local data = pckr.serialize(a, b, c, d, e)
local a, b, c, d, e = pckr.deserialize(data)

```


# running tests
run `main.lua` to run the tests.



## advanced / low level usage:
unlike other serialization libraries, `pckr` gives you full low level access
to serialization / deserialization functionality.

All this functionality is encapsulated in the namespace, `pckr.low`.

Here are the simplest functions:

```lua


-- sets a template for type keys, so it can be flattened.
pckr.low.set_template(vector_metatable, {"x", "y", "z"})
-- (These are the same as binser, except these can't be nested)
-- This means that `pckr` won't serialize any other keyed fields, 
-- (however `pckr` will still serialize the array part)


pckr.low.raw_serialize(buffer, x) -- serializes `table` whilst ignoring 
-- all custom serializers upon `x`.
-- NOTE: This function is especially useful inside of custom serializers!

pckr.low.raw_deserialize(reader, x) -- serializes `x` whilst ignoring custom serializers upon `x`.

-- NOTE: In order for templates and custom serializers to work, 
-- the metatable must be registered.
-- This is because if they aren't registered as resources, then upon
-- deserialization, `pckr` will create a copy of them.


pckr.low.set_custom_functions(metatable,
function(buffer, X, meta)
    -- custom serialization function. X is the data to be serialized.
    -- (`meta` is the metatable)
end,
function(reader, X, meta)
    -- custom deserialization function.
    -- X is a table that has been created by `pckr` automatically;
    -- put data in here.
end)
```

### Don't go past this point if you are just a casual user.

Here are all the other `pckr.low` definitions:
```lua
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
```
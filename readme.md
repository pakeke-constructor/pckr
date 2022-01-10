
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
namespace: `pckr.low`
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





pckr.low.set_serialize(metatable, function(buffer) ... end)

pckr.low.set_deserialize(metatable, function(reader) ... end)



```


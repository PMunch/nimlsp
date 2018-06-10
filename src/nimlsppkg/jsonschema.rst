JSON schema validation
======================

When working with JSON data in Nim you must ensure that all the keys you
require are present and that the values they store are of the correct type.
Failure to do so will result in exceptions and make your program fragile.
The ``jsonschema`` module implements a schema DSL that generates verifiers and
creators for structured JSON data. The DSL is based around TypeScript, but is
not 100% compatible (yet). At the end of the ``jsonschema.nim`` file are some
example of how to use the module. What follows is a commented explanation of
how the DSL works.

.. code:: nim
    jsonSchema: # The macro that parses the schema DSL
      # `CancelParams` here is the name we want to give this schema, it doesn't
      # verify against anything and is just use to refer to it in your code.
      CancelParams:
        # Optional fields are denoted with "?:" they aren't required to show up
        # in the JSON, but will get verified if they do. When you want to
        # create an object matching this schema you need to pass an Option[T]
        # type for it. This also shows how one key can have multiple different
        # allowed types. When you use the value you must check which of the
        # types is actually present.
        id?: int or string or float
        # Same as above, checks if a key is present, and verifies it's type if
        # it does. Note that with optional fields you have to check if it
        # actually exists in the JSON object before using them.
        something?: float

      WrapsCancelParams:
        # Referring to another schema declared in the same `jsonSchema` block
        # means that this is an object within this schema. The validator proc
        # has a `traverse` option, which defaults to true, that dictates if the
        # verification shall check nested schemas or not.
        cp: CancelParams
        # Neither this nor the `cp` field is optional, they have to exist in
        # the JSON object or it won't be valid.
        name: string

      # This style of declaration means that all the fields in `CancelParams`
      # will also be verified for `ExtendsCancelParams`. Any extra fields will
      # also be verified. In the generated `create` procedure the order is
      # extended arguments first, then the new arguments.
      ExtendsCancelParams extends CancelParams:
        name: string

      WithArrayAndAny:
        # This is an array declaration. Arrays are homongenous and all elements
        # will be verified against the type. In this case they will not be
        # verified if `traverse` is set to false, althought the array will be
        # checked to actually be an array.
        test?: CancelParams[]
        # This is exactly what you would expect, either an array of integers,
        # or a single float.
        ralph: int[] or float
        # The keyword `any` can be used for any JSON value, including arrays
        # and objects. In this case it will be verified that the field exists,
        # but it won't get checked in any way outside that.
        bob: any
        # JSON also has a `null` value, this can be specified with the `nil`
        # keyword. This is currently implemented as an enum `NilType` with a
        # single value `Nil`. So for an optional field you can specify its
        # absence with `none(NilType)` and with a value as `some(Nil)`
        john?: int or nil

      NameTest:
        # In cases where the name of the field would collide with a Nim keyword
        # you can quote it. The field is still checked for the same name, but
        # the argument name is mangled. By default a prefix of "the" is added,
        # but should this collide with something you can change the prefix with
        # `-d:ManglePrefix="<your mangle prefix>"
        "method": string
        "result": int
        "if": bool
        "type": float

As an example of the code generated this is what the above ``WithArrayAndAny``
would generate. Note that you can also get the code generated with
``-d:jsonSchemaDebug``.

.. code:: nim
    type
      WithArrayAndAny = distinct JsonNode

    proc isValid(data: JsonNode; schemaType: typedesc[WithArrayAndAny];
                traverse = true): bool =
      if data.kind != JObject:
        return false
      var fields = 2
      if data.hasKey("test"):
        fields += 1
        if data["test"].kind != JArray or
            (traverse and
            not data["test"].allIt(it.isValid(CancelParams))):
          return false
      if not data.hasKey("ralph"):
        return false
      if data["ralph"].kind != JArray or
          data["ralph"].anyIt(it.kind != Jint) and
          data["ralph"].kind != Jfloat:
        return false
      if not data.hasKey("bob"):
        return false
      if false:
        return false
      if data.hasKey("john"):
        fields += 1
        if data["john"].kind != Jint and
            data["john"].kind != JNull:
          return false
      if fields !=
          data.len:
        return false
      return true

    proc create(schemaType: typedesc[WithArrayAndAny]; test: Option[seq[CancelParams]];
               ralph: seq[int] or float; bob: JsonNode;
               john: Option[int] or Option[NilType]): WithArrayAndAny =
      var ret = newJObject()
      when test is
          Option[seq[CancelParams]]:
        if test.isSome:
          []=(ret, "test", newJArray())
          for i in test.get:
            ret["test"].add i.JsonNode
      when ralph is seq[int]:
        []=(ret, "ralph", newJArray())
        for i in ralph:
          ret["ralph"].add %i
      when ralph is float:
        []=(ret, "ralph", %ralph)
      when bob is JsonNode:
        []=(ret, "bob", bob.JsonNode)
      when john is
          Option[int]:
        if john.isSome:
          []=(ret, "john", %john.get)
      when john is
          Option[NilType]:
        if john.isSome:
          []=(ret, "john", newJNull())
      return ret.WithArrayAndAny


# Package

version       = "0.1.0"
author        = "PMunch"
description   = "Nim Language Server Protocol - nimlsp implements the Language Server Protocol"
license       = "MIT"
srcDir        = "src"
bin           = @["nimlsp"]

# Dependencies

requires "nim >= 0.19.0"
#requires "packedjson"
requires "astpatternmatching"
requires "jsonschema"

# nimble test does not work for me out of the box
task test, "Runs the test suite":
  #exec "nim c -r tests/test_messages.nim"
  exec "nim c -d:jsonSchemaDebug -r tests/test_messages2.nim"

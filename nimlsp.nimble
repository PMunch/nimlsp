# Package

version       = "0.1.0"
author        = "pmunch"
description   = "Nim Language Server Protocol - nimlsp implements Language Server Protocol"
license       = "MIT"
srcDir        = "src"
bin           = @["nimlsp"]

# Dependencies

requires "nim >= 0.18.1"
requires "packedjson"

# nimble test does not work for me out of the box
task test, "Runs the test suite":
  exec "nim c -r tests/test_messages.nim"

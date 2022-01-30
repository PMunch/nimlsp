# Package

version       = "0.4.0"
author        = "PMunch"
description   = "Nim Language Server Protocol - nimlsp implements the Language Server Protocol"
license       = "MIT"
srcDir        = "src"
bin           = @["nimlsp"]

# Dependencies

requires "nim >= 1.0.0"
requires "jsonschema >= 0.2.1"

# nimble test does not work for me out of the box
#task test, "Runs the test suite":
  #exec "nim c -r tests/test_messages.nim"
#  exec "nim c -d:debugLogging -d:jsonSchemaDebug -r tests/test_messages2.nim"

task debug, "Builds the language server":
  exec "nim c --threads:on -d:nimcore -d:nimsuggest -d:debugCommunication -d:debugLogging -o:nimlsp src/nimlsp"

before test:
  if not fileExists("nimlsp"):
    exec "nimble build"

task findNim, "Tries to find the current Nim installation":
  echo NimVersion
  echo currentSourcePath

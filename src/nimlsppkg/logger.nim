import os
let
  storage* = getTempDir() / "nimlsp"

when defined(debugLogging):
  discard existsOrCreateDir(storage)
  var logFile = open(storage / "nimlsp.log", fmWrite)

template debug*(args: varargs[string, `$`]) =
  when defined(debugLogging):
    stderr.write(join args)
    stderr.write("\n")
    logFile.write(join args)
    logFile.write("\n\n")
    logFile.flushFile()
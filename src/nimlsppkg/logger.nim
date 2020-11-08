import os
const
  storage* = getTempDir() / "nimlsp"

when defined(debugLogging):
  var logFile = open(storage / "nimlsp.log", fmWrite)

template debug*(args: varargs[string, `$`]) =
  when defined(debugLogging):
    stderr.write(join args)
    stderr.write("\n")
    logFile.write(join args)
    logFile.write("\n\n")
    logFile.flushFile()
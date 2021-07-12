import os,logging
let
  storage* = getTempDir() / "nimlsp"

let rollingLog = newRollingFileLogger(getHomeDir() / "nimlsp.com.log")
addHandler(rollingLog)

when defined(debugLogging):
  discard existsOrCreateDir(storage)
  var logFile = open(storage / "nimlsp.log", fmWrite)

template debug*(args: varargs[string, `$`]) =
  when defined(debugLogging):
    info(join args)
    info("\n")
    logFile.write(join args)
    logFile.write("\n\n")
    logFile.flushFile()
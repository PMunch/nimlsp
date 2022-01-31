import os, logging

const storage* = getTempDir() / "nimlsp"

let rollingLog = newRollingFileLogger(storage / "nimlsp.log")
addHandler(rollingLog)

template debugLog*(args: varargs[string, `$`]) =
  when defined(debugLogging):
    debug join(args)
    flushFile rollingLog.file

template infoLog*(args: varargs[string, `$`]) =
  when defined(debugLogging):
    info join(args)
    flushFile rollingLog.file

template errorLog*(args: varargs[string, `$`]) =
  when defined(debugLogging):
    error join(args)

template warnLog*(args: varargs[string, `$`]) =
  when defined(debugLogging):
    warn join(args)

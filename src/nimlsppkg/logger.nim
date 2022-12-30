import std/[logging, os]


let storage* = getTempDir() / "nimlsp-" & $getCurrentProcessId()
discard existsOrCreateDir(storage)
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

type FrameDirection* = enum In, Out

template frameLog*(direction: FrameDirection, args: varargs[string, `$`]) =
  let oldFmtStr = rollingLog.fmtStr
  case direction:
  of Out: rollingLog.fmtStr = "<< "
  of In: rollingLog.fmtStr = ">> "
  let msg = join(args)
  for line in msg.splitLines:
    info line
  flushFile rollingLog.file
  rollingLog.fmtStr = oldFmtStr


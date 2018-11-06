import osproc
import os
import strutils
import streams

type
  Suggestion* = object
    symkind*: string
    qualifiedPath*: string
    signature*: string
    filePath*: string
    line*: int
    column*: int
    docstring*: string
    quality*: int
    unknown*: string
  NimSuggest* = Process

proc parseSuggestion(sugstring: string): Suggestion =
  var x = 0
  for field in sugstring.split('\t'):
    case x:
      of 0: discard # We don't care what the command was
      of 1: result.symkind       = field
      of 2: result.qualifiedPath = field
      of 3: result.signature     = field
      of 4: result.filePath      = field
      of 5: result.line          = field.parseInt
      of 6: result.column        = field.parseInt
      of 7: result.docstring     = field
      of 8: result.quality       = field.parseInt
      of 9: result.unknown       = field
      else: discard # nimsuggest has added an extra field
    x += 1

proc startNimSuggest*(projectfile: string): NimSuggest =
  result = startProcess("nimsuggest", args = ["--v2", "--stdin", projectfile],
                        options = {poUsePath, poEchoCmd})

proc stopNimSuggest*(nimsuggest: NimSuggest): int =
  if nimsuggest.running:
    nimsuggest.terminate()
    result = nimsuggest.waitForExit()
    nimsuggest.close()
  else: result = -1

template createFullCommand(command: untyped) =
  proc command*(nimsuggest: NimSuggest, file: string, dirtyfile = "",
            line: int, col: int): seq[Suggestion] =
    if not nimsuggest.running:
      raise newException(IOError, "nimsuggest process is not running")
    nimsuggest.inputStream.writeLine("$1 $2$3:$4:$5" %
      [command.astToStr, file, (if dirtyfile.len > 0: ";$1" % [dirtyfile] else: ""), $line, $col])
    nimsuggest.inputStream.flush()
    var line = ""
    while line.len != 0 or result.len == 0:
      line = nimsuggest.outputStream.readLine
      if line.startsWith(command.astToStr):
        result.add line.parseSuggestion

template createFileOnlyCommand(command: untyped) =
  proc command*(nimsuggest: NimSuggest, file: string, dirtyfile = ""): seq[Suggestion] =
    if not nimsuggest.running:
      raise newException(IOError, "nimsuggest process is not running")
    nimsuggest.inputStream.writeLine("$1 $2$3" %
      [command.astToStr, file, (if dirtyfile.len > 0: ";$1" % [dirtyfile] else: "")])
    nimsuggest.inputStream.flush()
    var line = ""
    while line.len != 0 or result.len == 0:
      line = nimsuggest.outputStream.readLine
      if line.startsWith(command.astToStr):
        result.add line.parseSuggestion

createFullCommand(sug)
createFullCommand(con)
createFullCommand(def)
createFullCommand(use)
createFullCommand(dus)
createFileOnlyCommand(chk)
createFileOnlyCommand(`mod`)
createFileOnlyCommand(highlight)
createFileOnlyCommand(outline)
createFileOnlyCommand(known)


when isMainModule:
  var nimsuggest = startNimSuggest("/home/peter/Projects/nimlsp/tests/sugtest.nim")
  echo nimsuggest.sug("/home/peter/Projects/nimlsp/tests/sugtest.nim", dirtyfile = "/home/peter/Projects/nimlsp/tests/sugtest_t.nim", 6, 2)
  echo nimsuggest.stopNimSuggest()


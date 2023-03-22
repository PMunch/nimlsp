import std/[
    asyncdispatch,
    asyncnet,
    deques,
    os,
    osproc,
    sets,
    streams,
    strformat,
    strutils,
    times
  ],

  chronicles,
  asynctools/asyncpipe,
  faststreams/[asynctools_adapters, textio],

  ./messageenums


# === nimlangserver/pipes.nim start

when defined(windows):
  import winlean

  proc writeToPipe*(p: AsyncPipe, data: pointer, nbytes: int) =
    if writeFile(p.getWriteHandle, data, int32(nbytes), nil, nil) == 0:
      raiseOsError(osLastError())

else:
  import posix

  proc writeToPipe*(p: AsyncPipe, data: pointer, nbytes: int) =
    if posix.write(p.getWriteHandle, data, cint(nbytes)) < 0:
      raiseOsError(osLastError())

proc copyFileToPipe*(param: tuple[pipe: AsyncPipe, file: File]) {.thread.} =
  var
    inputStream = newFileStream(param.file)
    ch = "^"

  ch[0] = inputStream.readChar()

  while ch[0] != '\0':
    writeToPipe(param.pipe, ch[0].addr, 1)
    ch[0] = inputStream.readChar();
  closeWrite(param.pipe, false)

# === nimlangserver/pipes.nim end


# === nimlangserver/utils.nim start

proc catchOrQuit*(error: Exception) =
  if error of CatchableError:
    trace "Async operation ended with a recoverable error", err = error.msg
  else:
    fatal "Fatal exception reached", err = error.msg, stackTrace = getStackTrace()
    quit 1

proc traceAsyncErrors*(fut: Future) =
  fut.addCallback do ():
    if not fut.error.isNil:
      catchOrQuit fut.error[]

# === nimlangserver/utils.nim end


const REQUEST_TIMEOUT* = 120000

# coppied from Nim repo
type
  PrefixMatch* {.pure.} = enum
    None,   ## no prefix detected
    Abbrev  ## prefix is an abbreviation of the symbol
    Substr, ## prefix is a substring of the symbol
    Prefix, ## prefix does match the symbol

  IdeCmd* = enum
    ideNone, ideSug, ideCon, ideDef, ideUse, ideDus, ideChk, ideMod,
    ideHighlight, ideOutline, ideKnown, ideMsg, ideProject, ideType, ideExpand
  NimsuggestCallback = proc(self: Nimsuggest): void {.gcsafe.}

  Suggest* = ref object of RootObj
    section*: IdeCmd
    qualifiedPath*: seq[string] # part of 'qualifiedPath'
    filePath*: string
    line*: int                # Starts at 1
    column*: int              # Starts at 0
    doc*: string           # Not escaped (yet)
    forth*: string               # type
    quality*: range[0..100]   # matching quality
    isGlobal*: bool # is a global variable
    contextFits*: bool # type/non-type context matches
    prefix*: PrefixMatch
    symkind*: string
    scope*, localUsages*, globalUsages*: int # more usages is better
    tokenLen*: int
    version*: int
    endLine*: int
    endCol*: int

  SuggestCall* = ref object
    commandString: string
    future: Future[seq[Suggest]]
    command: string

  Nimsuggest* = ref object
    failed*: bool
    errorMessage*: string
    checkProjectInProgress*: bool
    needsCheckProject*: bool
    openFiles*: OrderedSet[string]
    successfullCall*: bool
    errorCallback: NimsuggestCallback
    process: Process
    port: int
    root: string
    requestQueue: Deque[SuggestCall]
    processing: bool
    timeout: int
    timeoutCallback: NimsuggestCallback

template benchmark(benchmarkName: string, code: untyped) =
  block:
    debug "Started...", benchmark = benchmarkName
    let t0 = epochTime()
    code
    let elapsed = epochTime() - t0
    let elapsedStr = elapsed.formatFloat(format = ffDecimal, precision = 3)
    debug "CPU Time", benchmark = benchmarkName, time = elapsedStr

func nimSymToLSPKind*(suggest: Suggest): CompletionItemKind =
  case suggest.symKind:
  of "skConst": CompletionItemKind.Value
  of "skEnumField": CompletionItemKind.Enum
  of "skForVar": CompletionItemKind.Variable
  of "skIterator": CompletionItemKind.Keyword
  of "skLabel": CompletionItemKind.Keyword
  of "skLet": CompletionItemKind.Value
  of "skMacro": CompletionItemKind.Snippet
  of "skMethod": CompletionItemKind.Method
  of "skParam": CompletionItemKind.Variable
  of "skProc": CompletionItemKind.Function
  of "skResult": CompletionItemKind.Value
  of "skTemplate": CompletionItemKind.Snippet
  of "skType": CompletionItemKind.Class
  of "skVar": CompletionItemKind.Field
  of "skFunc": CompletionItemKind.Function
  else: CompletionItemKind.Property

func nimSymToLSPSymbolKind*(suggest: string): SymbolKind =
  case suggest:
  of "skConst": SymbolKind.Constant
  of "skEnumField": SymbolKind.EnumMember
  of "skField": SymbolKind.Field
  of "skIterator": SymbolKind.Function
  of "skConverter": SymbolKind.Function
  of "skLet": SymbolKind.Variable
  of "skMacro": SymbolKind.Function
  of "skMethod": SymbolKind.Method
  of "skProc": SymbolKind.Function
  of "skTemplate": SymbolKind.Function
  of "skType": SymbolKind.Class
  of "skVar": SymbolKind.Variable
  of "skFunc": SymbolKind.Function
  else: SymbolKind.Function

func nimSymDetails*(suggest: Suggest): string =
  case suggest.symKind:
  of "skConst": "const " & suggest.qualifiedPath.join(".") & ": " & suggest.forth
  of "skEnumField": "enum " & suggest.forth
  of "skForVar": "for var of " & suggest.forth
  of "skIterator": suggest.forth
  of "skLabel": "label"
  of "skLet": "let of " & suggest.forth
  of "skMacro": "macro"
  of "skMethod": suggest.forth
  of "skParam": "param"
  of "skProc": suggest.forth
  of "skResult": "result"
  of "skTemplate": suggest.forth
  of "skType": "type " & suggest.qualifiedPath.join(".")
  of "skVar": "var of " & suggest.forth
  else: suggest.forth

const failedToken = "::Failed::"

proc parseQualifiedPath*(input: string): seq[string] =
  result = @[]
  var
    item = ""
    escaping = false

  for c in input:
    if c == '`':
      item = item & c
      escaping = not escaping
    elif escaping:
      item = item & c
    elif c == '.':
      result.add item
      item = ""
    else:
      item = item & c

  if item != "":
    result.add item

func `$`*(sug: Suggest): string =
  $sug[]

proc parseSuggest*(line: string): Suggest =
  let tokens = line.split('\t');
  if tokens.len < 8:
    error "Failed to parse: ", line = line
    raise newException(ValueError, fmt "Failed to parse line {line}")
  result = Suggest(
    qualifiedPath: tokens[2].parseQualifiedPath,
    filePath: tokens[4],
    line: parseInt(tokens[5]),
    column: parseInt(tokens[6]),
    doc: tokens[7].unescape(),
    forth: tokens[3],
    symKind: tokens[1],
    section: parseEnum[IdeCmd]("ide" & capitalizeAscii(tokens[0])))
  if tokens.len == 11:
    result.endLine = parseInt(tokens[9])
    result.endCol = parseInt(tokens[10])

func name*(sug: Suggest): string =
  return sug.qualifiedPath[^1]

func collapseByIdentifier*(sug: Suggest): string =
  fmt "{sug.qualifiedPath[^1]}__{sug.symKind}"

proc markFailed(self: Nimsuggest, errMessage: string) =
  self.failed = true
  self.errorMessage = errMessage
  if self.errorCallback != nil:
    self.errorCallback(self)

proc readPort(param: tuple[pipe: AsyncPipe, process: Process]) {.thread.} =
  try:
    var line = param.process.outputStream.readLine & "\n"
    writeToPipe(param.pipe, line[0].addr, line.len)
  except IOError:
    error "Failed to read nimsuggest port"
    var msg = failedToken & "\n"
    writeToPipe(param.pipe, msg[0].addr, msg.len)

proc logStderr(param: tuple[root: string, process: Process]) {.thread.} =
  try:
    var line = param.process.errorStream.readLine
    while line != "\0":
      stderr.writeLine fmt ">> {line}"
      line = param.process.errorStream.readLine
  except IOError:
    discard

proc stop*(self: Nimsuggest) =
  debug "Stopping nimsuggest for ", root = self.root
  try:
    self.process.kill()
    self.process.close()
  except Exception:
    discard

proc stopWithCode*(self: Nimsuggest): int =
  debug "Stopping nimsuggest for ", root = self.root
  try:
    self.process.kill()
    result = self.process.waitForExit()
    self.process.close()
  except Exception:
    discard

proc doWithTimeout*[T](fut: Future[T], timeout: int, s: string): owned(Future[bool]) =
  var retFuture = newFuture[bool]("asyncdispatch.`doWithTimeout`")
  var timeoutFuture = sleepAsync(timeout)
  fut.addCallback do ():
    if not retFuture.finished:
      retFuture.complete(true)

  timeoutFuture.addCallback do ():
    if not retFuture.finished:
      retFuture.complete(false)

  return retFuture

proc createNimsuggest*(root: string,
                       nimsuggestPath: string,
                       timeout: int,
                       timeoutCallback: NimsuggestCallback,
                       errorCallback: NimsuggestCallback,
                       workingDir = getCurrentDir()): Future[Nimsuggest] {.async, gcsafe.} =
  var
    pipe = createPipe(register = true)
    thread: Thread[tuple[pipe: AsyncPipe, process: Process]]
    stderrThread: Thread[tuple[root: string, process: Process]]
    input = pipe.asyncPipeInput
    fullPath = findExe(nimsuggestPath)

  info "Starting nimsuggest", root = root, timeout = timeout, path = nimsuggestPath,
    fullPath = fullPath, workingDir = workingDir

  result = Nimsuggest()
  result.requestQueue = Deque[SuggestCall]()
  result.root = root
  result.timeout = timeout
  result.timeoutCallback = timeoutCallback
  result.errorCallback = errorCallback

  if fullPath != "":
    result.process = startProcess(command = nimsuggestPath,
                                  workingDir = workingDir,
                                  args = @[root, "--v3", "--autobind"],
                                  options = {poUsePath})

    # all this is needed to avoid the need to block on the main thread.
    createThread(thread, readPort, (pipe: pipe, process: result.process))

    # copy stderr of log
    createThread(stderrThread, logStderr, (root: root, process: result.process))

    if input.readable:
      let line = await input.readLine
      if line == failedToken:
        result.markFailed "Nimsuggest process crashed."
      else:
        result.port = line.parseInt
        debug "Started nimsuggest", port = result.port, root = root
  else:
    error "Unable to start nimsuggest. Unable to find binary on the $PATH", nimsuggestPath = nimsuggestPath
    result.markFailed fmt "Unable to start nimsuggest. `{nimsuggestPath}` is not present on the PATH"

proc createNimsuggest*(root: string): Future[Nimsuggest] {.gcsafe.} =
  result = createNimsuggest(root, "nimsuggest", REQUEST_TIMEOUT,
                            proc (ns: Nimsuggest) = discard,
                            proc (ns: Nimsuggest) = discard)

proc processQueue(self: Nimsuggest): Future[void] {.async.}=
  debug "processQueue", size = self.requestQueue.len
  while self.requestQueue.len != 0:
    let req = self.requestQueue.popFirst
    logScope:
      command = req.commandString
    if req.future.finished:
      debug "Call cancelled before executed", command = req.command
    elif self.failed:
      debug "Nimsuggest is not working, returning empty result..."
      req.future.complete @[]
    else:
      benchmark req.commandString:
        let socket = newAsyncSocket()
        var res: seq[Suggest] = @[]

        if not self.timeoutCallback.isNil:
          debug "timeoutCallback is set", timeout = self.timeout
          doWithTimeout(req.future, self.timeout, fmt "running {req.commandString}").addCallback do (f: Future[bool]):
            if not f.failed and not f.read():
              debug "Calling restart"
              self.timeoutCallback(self)

        await socket.connect("127.0.0.1", Port(self.port))
        await socket.send(req.commandString & "\c\L")

        const bufferSize = 1024 * 1024 * 4
        var buffer:seq[byte] = newSeq[byte](bufferSize);

        var content = "";
        var received = await socket.recvInto(addr buffer[0], bufferSize)

        while received != 0:
          let chunk = newString(received)
          copyMem(chunk[0].unsafeAddr, buffer[0].unsafeAddr, received)
          content = content & chunk
          received = await socket.recvInto(addr buffer, bufferSize)

        for lineStr  in content.splitLines:
          if lineStr != "":
            if req.command != "known":
              res.add parseSuggest(lineStr)
            else:
              let sug = Suggest()
              sug.section = ideKnown
              sug.forth = lineStr
              res.add sug

        if (content == ""):
          self.markFailed "Server crashed/socket closed."
          debug "Server socket closed"
          if not req.future.finished:
            debug "Call cancelled before sending error", command = req.command
            req.future.fail newException(CatchableError, "Server crashed/socket closed.")
        if not req.future.finished:
          debug "Sending result(s)", length = res.len
          req.future.complete res
          self.successfullCall = true
          socket.close()
        else:
          debug "Call was cancelled before sending the result", command = req.command
          socket.close()
  self.processing = false

proc call*(self: Nimsuggest, command: string, file: string, dirtyFile: string,
    line: int, column: int, tag = ""): Future[seq[Suggest]] =
  result = Future[seq[Suggest]]()
  let commandString = if dirtyFile != "":
                        fmt "{command} \"{file}\";\"{dirtyFile}\":{line}:{column}{tag}"
                      else:
                        fmt "{command} \"{file}\":{line}:{column}{tag}"
  self.requestQueue.addLast(
    SuggestCall(commandString: commandString, future: result, command: command))

  if not self.processing:
    self.processing = true
    traceAsyncErrors processQueue(self)

template createFullCommand(command: untyped) {.dirty.} =
  proc command*(self: Nimsuggest, file: string, dirtyfile = "",
                line: int, col: int, tag = ""): Future[seq[Suggest]] =
    return self.call(astToStr(command), file, dirtyfile, line, col, tag)

template createFileOnlyCommand(command: untyped) {.dirty.} =
  proc command*(self: Nimsuggest, file: string, dirtyfile = ""): Future[seq[Suggest]] =
    return self.call(astToStr(command), file, dirtyfile, 0, 0)

template createGlobalCommand(command: untyped) {.dirty.} =
  proc command*(self: Nimsuggest): Future[seq[Suggest]] =
    return self.call(astToStr(command), "-", "", 0, 0)

# create commands
createFullCommand(sug)
createFullCommand(con)
createFullCommand(def)
createFullCommand(declaration)
createFullCommand(use)
createFullCommand(expand)
createFullCommand(highlight)
createFullCommand(type)
createFileOnlyCommand(chk)
createFileOnlyCommand(chkFile)
createFileOnlyCommand(changed)
createFileOnlyCommand(outline)
createFileOnlyCommand(known)
createFileOnlyCommand(globalSymbols)
createGlobalCommand(recompile)

proc `mod`*(nimsuggest: Nimsuggest, file: string, dirtyfile = ""): Future[seq[Suggest]] =
  return nimsuggest.call("ideMod", file, dirtyfile, 0, 0)

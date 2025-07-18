import std/[algorithm, asyncdispatch, asyncfile, hashes, os, osproc, sets,
            streams, strformat, strutils, tables, uri]
import asynctools/asyncproc
import nimlsppkg/[baseprotocol, logger, suggestlib, utfmapping]
include nimlsppkg/[messages, messageenums]


const
  version = block:
    var version = "0.0.0"
    let nimbleFile = staticRead(currentSourcePath().parentDir /../ "nimlsp.nimble")
    for line in nimbleFile.splitLines:
      let keyval = line.split('=')
      if keyval.len == 2:
        if keyval[0].strip == "version":
          version = keyval[1].strip(chars = Whitespace + {'"'})
          break
    version
  # This is used to explicitly set the default source path
  explicitSourcePath {.strdefine.} = getCurrentCompilerExe().parentDir.parentDir

type
  UriParseError* = object of Defect
    uri: string

var nimpath = explicitSourcePath

infoLog("Version: ", version)
infoLog("explicitSourcePath: ", explicitSourcePath)
for i in 1..paramCount():
  infoLog("Argument ", i, ": ", paramStr(i))

var
  gotShutdown = false
  initialized = false
  projectFiles = initTable[string, tuple[nimsuggest: NimSuggest, openFiles: OrderedSet[string], dirtyFiles: HashSet[string]]]()
  openFiles = initTable[string, tuple[projectFile: string, fingerTable: seq[seq[tuple[u16pos, offset: int]]]]]()

template whenValid(data, kind, body) =
  if data.isValid(kind, allowExtra = true):
    var data = kind(data)
    body
  else:
    debugLog("Unable to parse data as ", kind)

template whenValidStrict(data, kind, body) =
  if data.isValid(kind):
    var data = kind(data)
    body
  else:
    debugLog("Unable to parse data as ", kind)

proc getFileStash(fileuri: string): string =
  return storage / (hash(fileuri).toHex & ".nim")

template textDocumentRequest(message, kind, name, body) {.dirty.} =
  if message["params"].isSome:
    let name = message["params"].unsafeGet
    whenValid(name, kind):
      let
        fileuri = name["textDocument"]["uri"].getStr
        filestash = storage / (hash(fileuri).toHex & ".nim" )
      debugLog "Got request for URI: ", fileuri, " copied to ", filestash
      when kind isnot DocumentSymbolParams:
        let
          rawLine = name["position"]["line"].getInt
          rawChar = name["position"]["character"].getInt
      body

template textDocumentNotification(message, kind, name, body) {.dirty.} =
  if message["params"].isSome:
    let name = message["params"].unsafeGet
    whenValid(name, kind):
      if "languageId" notin name["textDocument"] or name["textDocument"]["languageId"].getStr == "nim":
        let
          fileuri = name["textDocument"]["uri"].getStr
          filestash = storage / (hash(fileuri).toHex & ".nim" )
        body

proc pathToUri(path: string): string =
  # This is a modified copy of encodeUrl in the uri module. This doesn't encode
  # the / character, meaning a full file path can be passed in without breaking
  # it.
  result = newStringOfCap(path.len + path.len shr 2) # assume 12% non-alnum-chars
  when defined(windows):
    result.add '/'
  for c in path:
    case c
    # https://tools.ietf.org/html/rfc3986#section-2.3
    of 'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~', '/': result.add c
    of '\\':
      when defined(windows):
        result.add '/'
      else:
        result.add '%'
        result.add toHex(ord(c), 2)
    else:
      result.add '%'
      result.add toHex(ord(c), 2)

proc uriToPath(uri: string): string =
  ## Convert an RFC 8089 file URI to a native, platform-specific, absolute path.
  #let startIdx = when defined(windows): 8 else: 7
  #normalizedPath(uri[startIdx..^1])
  let parsed = uri.parseUri
  if parsed.scheme != "file":
    var e = newException(UriParseError, &"Invalid scheme: {parsed.scheme}, only \"file\" is supported")
    e.uri = uri
    raise e
  if parsed.hostname != "":
    var e = newException(UriParseError, &"Invalid hostname: {parsed.hostname}, only empty hostname is supported")
    e.uri = uri
    raise e
  return normalizedPath(
    when defined(windows):
      parsed.path[1..^1]
    else:
      parsed.path).decodeUrl

proc parseId(node: JsonNode): int =
  if node.kind == JString:
    parseInt(node.getStr)
  elif node.kind == JInt:
    node.getInt
  else:
    raise newException(MalformedFrame, "Invalid id node: " & repr(node))

proc respond(outs: Stream | AsyncFile, request: RequestMessage, data: JsonNode) {.multisync.} =
  let resp = create(ResponseMessage, "2.0", parseId(request["id"]), some(data), none(ResponseError)).JsonNode
  await outs.sendJson resp

proc error(outs: Stream | AsyncFile, request: RequestMessage, errorCode: ErrorCode, message: string, data: JsonNode) {.multisync.} =
  let resp = create(ResponseMessage, "2.0", parseId(request["id"]), none(JsonNode), some(create(ResponseError, ord(errorCode), message, data))).JsonNode
  await outs.sendJson resp

proc notify(outs: Stream | AsyncFile, notification: string, data: JsonNode) {.multisync.} =
  let resp = create(NotificationMessage, "2.0", notification, some(data)).JsonNode
  await outs.sendJson resp

type Certainty = enum
  None,
  Folder,
  Cfg,
  Nimble

proc getProjectFile(fileUri: string): string =
  let file = fileUri.decodeUrl
  result = file
  let (dir, _, _) = result.splitFile()
  var
    path = dir
    certainty = None
  while not path.isRootDir:
    let
      (dir, fname, ext) = path.splitFile()
      current = fname & ext
    if fileExists(path / current.addFileExt(".nim")) and certainty <= Folder:
      result = path / current.addFileExt(".nim")
      certainty = Folder
    if fileExists(path / current.addFileExt(".nim")) and
      (fileExists(path / current.addFileExt(".nim.cfg")) or
      fileExists(path / current.addFileExt(".nims"))) and certainty <= Cfg:
      result = path / current.addFileExt(".nim")
      certainty = Cfg
    if certainty <= Nimble:
      for nimble in walkFiles(path / "*.nimble"):
        let info = osproc.execProcess("nimble dump " & nimble, options = {osproc.poEvalCommand, osproc.poUsePath})
        var sourceDir, name: string
        for line in info.splitLines:
          if line.startsWith("srcDir"):
            sourceDir = path / line[(1 + line.find '"')..^2]
          if line.startsWith("name"):
            name = line[(1 + line.find '"')..^2]
        let projectFile = sourceDir / (name & ".nim")
        if sourceDir.len != 0 and name.len != 0 and
            file.isRelativeTo(sourceDir) and fileExists(projectFile):
          result = projectFile
          certainty = Nimble
    path = dir
  debugLog "Found project file " & result & " for input file " & fileUri

template getNimsuggest(fileuri: string): Nimsuggest =
  projectFiles[openFiles[fileuri].projectFile].nimsuggest

if paramCount() == 1:
  case paramStr(1):
    of "--help":
      echo "Usage: nimlsp [OPTION | PATH]\n"
      echo "--help, shows this message"
      echo "--version, shows only the version"
      echo "PATH, path to the Nim source directory, defaults to \"", nimpath, "\""
      quit 0
    of "--version":
      echo "nimlsp v", version, " - built for Nim version ", NimVersion
      when defined(debugLogging): echo "Compiled with debug logging"
      when defined(debugCommunication): echo "Compiled with communication logging"
      quit 0
    else: nimpath = expandFilename(paramStr(1))
if not fileExists(nimpath / "config/nim.cfg"):
  stderr.write &"""Unable to find "config/nim.cfg" in "{nimpath
  }". Supply the Nim project folder by adding it as an argument.
"""
  quit 1

proc checkVersion(outs: Stream | AsyncFile) {.multisync.} =
  let
    nimoutputTuple =
      when outs is AsyncFile: await asyncproc.execProcess("nim --version", options = {asyncproc.poEvalCommand, asyncproc.poUsePath})
      else: osproc.execCmdEx("nim --version", options = {osproc.poEvalCommand, osproc.poUsePath})
  if nimoutputTuple.exitcode == 0:
    let
      nimoutput = nimoutputTuple.output
      versionStart = "Nim Compiler Version ".len
      version = nimoutput[versionStart..<nimoutput.find(" ", versionStart)]
      #hashStart = nimoutput.find("git hash") + 10
      #hash = nimoutput[hashStart..nimoutput.find("\n", hashStart)]
    if version != NimVersion:
      await outs.notify("window/showMessage", create(ShowMessageParams, MessageType.Warning.int, message = "Current Nim version does not match the one NimLSP is built against " & version & " != " & NimVersion).JsonNode)

proc main(ins: Stream | AsyncFile, outs: Stream | AsyncFile) {.multisync.} =
  while true:
    try:
      debugLog "Trying to read frame"
      let frame = await ins.readFrame
      debugLog "Got frame"
      let message = frame.parseJson
      whenValidStrict(message, RequestMessage):
        debugLog "Got valid Request message of type ", message["method"].getStr
        if not initialized and message["method"].getStr != "initialize":
          await outs.error(message, ServerNotInitialized, "Unable to accept requests before being initialized", newJNull())
          continue
        case message["method"].getStr:
          of "shutdown":
            debugLog "Got shutdown request, answering"
            let resp = newJNull()
            await outs.respond(message, resp)
            gotShutdown = true
          of "initialize":
            debugLog "Got initialize request, answering"
            initialized = true
            let resp = create(InitializeResult, create(ServerCapabilities,
              textDocumentSync = some(create(TextDocumentSyncOptions,
                openClose = some(true),
                change = some(TextDocumentSyncKind.Full.int),
                willSave = some(false),
                willSaveWaitUntil = some(false),
                save = some(create(SaveOptions, some(true)))
              )), # ?: TextDocumentSyncOptions or int or float
              hoverProvider = some(true), # ?: bool
              completionProvider = some(create(CompletionOptions,
                resolveProvider = some(false),
                triggerCharacters = some(@["."])
              )), # ?: CompletionOptions
              signatureHelpProvider = some(create(SignatureHelpOptions,
                triggerCharacters = some(@["(", ","])
              )), # ?: SignatureHelpOptions
              definitionProvider = some(true), #?: bool
              typeDefinitionProvider = none(bool), #?: bool or TextDocumentAndStaticRegistrationOptions
              implementationProvider = none(bool), #?: bool or TextDocumentAndStaticRegistrationOptions
              referencesProvider = some(true), #?: bool
              documentHighlightProvider = none(bool), #?: bool
              documentSymbolProvider = some(true), #?: bool
              workspaceSymbolProvider = none(bool), #?: bool
              codeActionProvider = none(bool), #?: bool
              codeLensProvider = none(CodeLensOptions), #?: CodeLensOptions
              documentFormattingProvider = none(bool), #?: bool
              documentRangeFormattingProvider = none(bool), #?: bool
              documentOnTypeFormattingProvider = none(DocumentOnTypeFormattingOptions), #?: DocumentOnTypeFormattingOptions
              renameProvider = some(true), #?: bool
              documentLinkProvider = none(DocumentLinkOptions), #?: DocumentLinkOptions
              colorProvider = none(bool), #?: bool or ColorProviderOptions or TextDocumentAndStaticRegistrationOptions
              executeCommandProvider = none(ExecuteCommandOptions), #?: ExecuteCommandOptions
              workspace = none(WorkspaceCapability), #?: WorkspaceCapability
              experimental = none(JsonNode) #?: any
            )).JsonNode
            await outs.respond(message,resp)
            when outs is AsyncFile:
              await checkVersion(outs)
            else:
              checkVersion(outs)
          of "textDocument/completion":
            message.textDocumentRequest(CompletionParams, compRequest):
              debugLog "Running equivalent of: sug ", uriToPath(fileuri), ";", filestash, ":",
                rawLine + 1, ":",
                openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
              let suggestions = getNimsuggest(fileuri).sug(uriToPath(fileuri), dirtyfile = filestash,
                rawLine + 1,
                openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
              )
              debugLog "Found suggestions: ",
                suggestions[0..<min(suggestions.len, 10)],
                if suggestions.len > 10: &" and {suggestions.len-10} more" else: ""
              var
                completionItems = newJarray()
                seenLabels: CountTable[string]
                addedSuggestions: HashSet[string]
              for suggestion in suggestions:
                seenLabels.inc suggestion.collapseByIdentifier
              for i in 0..suggestions.high:
                let
                  suggestion = suggestions[i]
                  collapsed = suggestion.collapseByIdentifier
                if not addedSuggestions.contains collapsed:
                  addedSuggestions.incl collapsed
                  let
                    seenTimes = seenLabels[collapsed]
                    detail =
                      if seenTimes == 1: some(nimSymDetails(suggestion))
                      else: some(&"[{seenTimes} overloads]")
                  completionItems.add create(CompletionItem,
                    label = suggestion.qualifiedPath[^1].strip(chars = {'`'}),
                    kind = some(nimSymToLSPKind(suggestion).int),
                    detail = detail,
                    documentation = some(suggestion.doc),
                    deprecated = none(bool),
                    preselect = none(bool),
                    sortText = some(fmt"{i:04}"),
                    filterText = none(string),
                    insertText = none(string),
                    insertTextFormat = none(int),
                    textEdit = none(TextEdit),
                    additionalTextEdits = none(seq[TextEdit]),
                    commitCharacters = none(seq[string]),
                    command = none(Command),
                    data = none(JsonNode)
                  ).JsonNode
              await outs.respond(message, completionItems)
          of "textDocument/hover":
            message.textDocumentRequest(TextDocumentPositionParams, hoverRequest):
              debugLog "Running equivalent of: def ", uriToPath(fileuri), ";", filestash, ":",
                rawLine + 1, ":",
                openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
              let suggestions = getNimsuggest(fileuri).def(uriToPath(fileuri), dirtyfile = filestash,
                rawLine + 1,
                openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
              )
              debugLog "Found suggestions: ",
                suggestions[0..<min(suggestions.len, 10)],
                if suggestions.len > 10: &" and {suggestions.len-10} more" else: ""
              var resp: JsonNode
              if suggestions.len == 0:
                resp = newJNull()
              else:
                var label = suggestions[0].qualifiedPath.join(".")
                if suggestions[0].forth != "":
                  label &= ": "
                  label &= suggestions[0].forth
                let
                  rangeopt =
                    some(create(Range,
                      create(Position, rawLine, rawChar),
                      create(Position, rawLine, rawChar + suggestions[0].qualifiedPath[^1].len)
                    ))
                  markedString = create(MarkedStringOption, "nim", label)
                if suggestions[0].doc != "":
                  resp = create(Hover,
                    @[
                      markedString,
                      create(MarkedStringOption, "", suggestions[0].doc),
                    ],
                    rangeopt
                  ).JsonNode
                else:
                  resp = create(Hover, markedString, rangeopt).JsonNode;
                await outs.respond(message, resp)
          of "textDocument/references":
            message.textDocumentRequest(ReferenceParams, referenceRequest):
              debugLog "Running equivalent of: use ", uriToPath(fileuri), ";", filestash, ":",
                rawLine + 1, ":",
                openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
              let suggestions = getNimsuggest(fileuri).use(uriToPath(fileuri), dirtyfile = filestash,
                rawLine + 1,
                openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
              )
              debugLog "Found suggestions: ",
                suggestions[0..<min(suggestions.len, 10)],
                if suggestions.len > 10: &" and {suggestions.len-10} more" else: ""
              var response = newJarray()
              for suggestion in suggestions:
                if suggestion.section == ideUse or referenceRequest["context"]["includeDeclaration"].getBool:
                  response.add create(Location,
                    "file://" & pathToUri(suggestion.filepath),
                    create(Range,
                      create(Position, suggestion.line-1, suggestion.column),
                      create(Position, suggestion.line-1, suggestion.column + suggestion.qualifiedPath[^1].len)
                    )
                  ).JsonNode
              if response.len == 0:
                await outs.respond(message, newJNull())
              else:
                await outs.respond(message, response)
          of "textDocument/rename":
            message.textDocumentRequest(RenameParams, renameRequest):
              debugLog "Running equivalent of: use ", uriToPath(fileuri), ";", filestash, ":",
                rawLine + 1, ":",
                openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
              let suggestions = getNimsuggest(fileuri).use(uriToPath(fileuri), dirtyfile = filestash,
                rawLine + 1,
                openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
              )
              debugLog "Found suggestions: ",
                suggestions[0..<min(suggestions.len, 10)],
                if suggestions.len > 10: &" and {suggestions.len-10} more" else: ""
              var resp: JsonNode
              if suggestions.len == 0:
                resp = newJNull()
              else:
                var textEdits = newJObject()
                for suggestion in suggestions:
                  let uri = "file://" & pathToUri(suggestion.filepath)
                  if uri notin textEdits:
                    textEdits[uri] = newJArray()
                  textEdits[uri].add create(TextEdit, create(Range,
                      create(Position, suggestion.line-1, suggestion.column),
                      create(Position, suggestion.line-1, suggestion.column + suggestion.qualifiedPath[^1].len)
                    ),
                    renameRequest["newName"].getStr
                  ).JsonNode
                resp = create(WorkspaceEdit,
                  some(textEdits),
                  none(seq[TextDocumentEdit])
                ).JsonNode
                await outs.respond(message, resp)
          of "textDocument/definition":
            message.textDocumentRequest(TextDocumentPositionParams, definitionRequest):
              debugLog "Running equivalent of: def ", uriToPath(fileuri), ";", filestash, ":",
                rawLine + 1, ":",
                openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
              let declarations = getNimsuggest(fileuri).def(uriToPath(fileuri), dirtyfile = filestash,
                rawLine + 1,
                openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
              )
              debugLog "Found suggestions: ",
                declarations[0..<min(declarations.len, 10)],
                if declarations.len > 10: &" and {declarations.len-10} more" else: ""
              var resp: JsonNode
              if declarations.len == 0:
                resp = newJNull()
              else:
                resp = newJarray()
                for declaration in declarations:
                  resp.add create(Location,
                    "file://" & pathToUri(declaration.filepath),
                    create(Range,
                      create(Position, declaration.line-1, declaration.column),
                      create(Position, declaration.line-1, declaration.column + declaration.qualifiedPath[^1].len)
                    )
                  ).JsonNode
              await outs.respond(message, resp)
          of "textDocument/documentSymbol":
            message.textDocumentRequest(DocumentSymbolParams, symbolRequest):
              debugLog "Running equivalent of: outline ", uriToPath(fileuri),
                        ";", filestash
              let syms = getNimsuggest(fileuri).outline(
                uriToPath(fileuri),
                dirtyfile = filestash
              )
              debugLog "Found outlines: ", syms[0..<min(syms.len, 10)],
                        if syms.len > 10: &" and {syms.len-10} more" else: ""
              var resp: JsonNode
              if syms.len == 0:
                resp = newJNull()
              else:
                resp = newJarray()
                for sym in syms.sortedByIt((it.line,it.column,it.quality)):
                  if sym.qualifiedPath.len != 2:
                    continue
                  resp.add create(
                    SymbolInformation,
                    sym.name[],
                    nimSymToLSPKind(sym.symKind).int,
                    some(false),
                    create(Location,
                    "file://" & pathToUri(sym.filepath),
                      create(Range,
                        create(Position, sym.line-1, sym.column),
                        create(Position, sym.line-1, sym.column + sym.qualifiedPath[^1].len)
                      )
                    ),
                    none(string)
                  ).JsonNode
              await outs.respond(message, resp)
          of "textDocument/signatureHelp":
            message.textDocumentRequest(TextDocumentPositionParams, sigHelpRequest):
              debugLog "Running equivalent of: con ", uriToPath(fileuri), ";", filestash, ":",
                rawLine + 1, ":",
                openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
              let suggestions = getNimsuggest(fileuri).con(uriToPath(fileuri), dirtyfile = filestash, rawLine + 1, rawChar)
              var signatures = newSeq[SignatureInformation]()
              for suggestion in suggestions:
                var label = suggestion.qualifiedPath.join(".")
                if suggestion.forth != "":
                  label &= ": "
                  label &= suggestion.forth
                signatures.add create(SignatureInformation,
                  label = label,
                  documentation = some(suggestion.doc),
                  parameters = none(seq[ParameterInformation])
                )
              let resp = create(SignatureHelp,
                signatures = signatures,
                activeSignature = some(0),
                activeParameter = some(0)
              ).JsonNode
              await outs.respond(message, resp)
          else:
            debugLog "Unknown request"
            await outs.error(message, InvalidRequest, "Unknown request: " & frame, newJObject())
        continue
      whenValidStrict(message, NotificationMessage):
        debugLog "Got valid Notification message of type ", message["method"].getStr
        if not initialized and message["method"].getStr != "exit":
          continue
        case message["method"].getStr:
          of "exit":
            debugLog "Exiting"
            if gotShutdown:
              quit 0
            else:
              quit 1
          of "initialized":
            debugLog "Properly initialized"
          of "textDocument/didOpen":
            message.textDocumentNotification(DidOpenTextDocumentParams, textDoc):
              let
                file = open(filestash, fmWrite)
                projectFile = getProjectFile(uriToPath(fileuri))
              debugLog "New document opened for URI: ", fileuri, " saving to ", filestash
              openFiles[fileuri] = (
                #nimsuggest: initNimsuggest(uriToPath(fileuri)),
                projectFile: projectFile,
                fingerTable: @[]
              )

              if projectFile notin projectFiles:
                debugLog "Initialising project with ", projectFile, ":", nimpath
                projectFiles[projectFile] = (nimsuggest: initNimsuggest(projectFile, nimpath), openFiles: initOrderedSet[string](), dirtyFiles: initHashSet[string]())
              projectFiles[projectFile].openFiles.incl(fileuri)
              projectFiles[projectFile].dirtyFiles.incl(filestash)

              for line in textDoc["textDocument"]["text"].getStr.splitLines:
                openFiles[fileuri].fingerTable.add line.createUTFMapping()
                file.writeLine line
              file.close()
          of "textDocument/didChange":
            message.textDocumentNotification(DidChangeTextDocumentParams, textDoc):
              let file = open(filestash, fmWrite)
              debugLog "Got document change for URI: ", fileuri, " saving to ", filestash
              openFiles[fileuri].fingerTable = @[]
              for line in textDoc["contentChanges"][0]["text"].getStr.splitLines:
                openFiles[fileuri].fingerTable.add line.createUTFMapping()
                file.writeLine line
              file.close()
              projectFiles[openFiles[fileuri].projectFile].dirtyFiles.incl(filestash)

              # Notify nimsuggest about a file modification.
              discard getNimsuggest(fileuri).mod(uriToPath(fileuri), dirtyfile = filestash)
          of "textDocument/didClose":
            message.textDocumentNotification(DidCloseTextDocumentParams, textDoc):
              let projectFile = getProjectFile(uriToPath(fileuri))
              debugLog "Got document close for URI: ", fileuri, " copied to ", filestash
              projectFiles[projectFile].openFiles.excl(fileuri)
              if projectFiles[projectFile].openFiles.len == 0:
                debugLog "No more open files for project ", projectFile
                debugLog "Cleaning up dirty files"
                for dirtyfile in projectFiles[openFiles[fileuri].projectFile].dirtyFiles:
                  removeFile(dirtyfile)
                debugLog "Deleting context"
                projectFiles.del(projectFile)
              openFiles.del(fileuri)
          of "textDocument/didSave":
            message.textDocumentNotification(DidSaveTextDocumentParams, textDoc):
              if textDoc["text"].isSome:
                let file = open(filestash, fmWrite)
                debugLog "Got document save for URI: ", fileuri, " saving to ", filestash
                openFiles[fileuri].fingerTable = @[]
                for line in textDoc["text"].unsafeGet.getStr.splitLines:
                  openFiles[fileuri].fingerTable.add line.createUTFMapping()
                  file.writeLine line
                file.close()
                projectFiles[openFiles[fileuri].projectFile].dirtyFiles.incl(filestash)
              debugLog "fileuri: ", fileuri, ", project file: ", openFiles[fileuri].projectFile, ", dirtyfile: ", filestash

              let diagnostics = getNimsuggest(fileuri).chk(uriToPath(fileuri), dirtyfile = filestash)
              debugLog "Got diagnostics: ",
                diagnostics[0..<min(diagnostics.len, 10)],
                if diagnostics.len > 10: &" and {diagnostics.len-10} more" else: ""
              var response: seq[Diagnostic]
              for diagnostic in diagnostics:
                if diagnostic.line == 0:
                  continue

                if diagnostic.filePath != uriToPath(fileuri):
                  continue
                # Try to guess the size of the identifier
                let
                  message = diagnostic.doc
                  endcolumn = diagnostic.column + message.rfind('\'') - message.find('\'') - 1
                response.add create(Diagnostic,
                  create(Range,
                    create(Position, diagnostic.line-1, diagnostic.column),
                    create(Position, diagnostic.line-1, max(diagnostic.column, endcolumn))
                  ),
                  some(case diagnostic.forth:
                    of "Error": DiagnosticSeverity.Error.int
                    of "Hint": DiagnosticSeverity.Hint.int
                    of "Warning": DiagnosticSeverity.Warning.int
                    else: DiagnosticSeverity.Error.int),
                  none(int),
                  some("nimsuggest chk"),
                  message,
                  none(seq[DiagnosticRelatedInformation])
                )

              # Invoke chk on all open files.
              let projectFile = openFiles[fileuri].projectFile
              for f in projectFiles[projectFile].openFiles.items:
                let diagnostics = getNimsuggest(f).chk(uriToPath(f), dirtyfile = getFileStash(f))
                debugLog "Got diagnostics: ",
                  diagnostics[0..<min(diagnostics.len, 10)],
                  if diagnostics.len > 10: &" and {diagnostics.len-10} more" else: ""

                var response: seq[Diagnostic]
                for diagnostic in diagnostics:
                  if diagnostic.line == 0:
                    continue

                  if diagnostic.filePath != uriToPath(f):
                    continue
                  # Try to guess the size of the identifier
                  let
                    message = diagnostic.doc
                    endcolumn = diagnostic.column + message.rfind('\'') - message.find('\'') - 1

                  response.add create(
                    Diagnostic,
                    create(Range,
                      create(Position, diagnostic.line-1, diagnostic.column),
                      create(Position, diagnostic.line-1, max(diagnostic.column, endcolumn))
                    ),
                    some(case diagnostic.forth:
                      of "Error": DiagnosticSeverity.Error.int
                      of "Hint": DiagnosticSeverity.Hint.int
                      of "Warning": DiagnosticSeverity.Warning.int
                      else: DiagnosticSeverity.Error.int),
                    none(int),
                    some("nimsuggest chk"),
                    message,
                    none(seq[DiagnosticRelatedInformation])
                  )
                let resp = create(PublishDiagnosticsParams, f, response).JsonNode
                await outs.notify("textDocument/publishDiagnostics", resp)
              let resp = create(PublishDiagnosticsParams,
                fileuri,
                response).JsonNode
              await outs.notify("textDocument/publishDiagnostics", resp)
          else:
            warnLog "Got unknown notification message"
        continue
    except UriParseError as e:
      warnLog "Got exception parsing URI: ", e.msg
      continue
    except IOError as e:
      errorLog "Got IOError: ", e.msg
      break
    except CatchableError as e:
      warnLog "Got exception: ", e.msg
      continue

when defined(windows):
  var
    ins = newFileStream(stdin)
    outs = newFileStream(stdout)
  main(ins, outs)
else:
  var
    ins = newAsyncFile(stdin.getOsFileHandle().AsyncFD)
    outs = newAsyncFile(stdout.getOsFileHandle().AsyncFD)
  waitFor main(ins, outs)

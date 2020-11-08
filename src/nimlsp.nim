import nimlsppkg / [baseprotocol, utfmapping, suggestlib]
include nimlsppkg / messages
import streams
import tables
import strutils
import os
import hashes
import uri
import algorithm

const
  storage = getTempDir() / "nimlsp"
  version = block:
    var version = "0.0.0"
    let nimbleFile = staticRead(currentSourcePath().parentDir().parentDir() / "nimlsp.nimble")
    for line in nimbleFile.splitLines:
      let keyval = line.split("=")
      if keyval.len == 2:
        if keyval[0].strip == "version":
          version = keyval[1].strip(chars = Whitespace + {'"'})
          break
    version
  # This is used to explicitly set the default source path
  explicitSourcePath {.strdefine.} = getCurrentCompilerExe().parentDir.parentDir

var nimpath = explicitSourcePath

discard existsOrCreateDir(storage)

when defined(debugLogging):
  var logFile = open(storage / "nimlsp.log", fmWrite)

template debugEcho(args: varargs[string, `$`]) =
  when defined(debugLogging):
    stderr.write(join args)
    stderr.write("\n")
    logFile.write(join args)
    logFile.write("\n\n")
    logFile.flushFile()

debugEcho("Version: " & version)
debugEcho("explicitSourcePath: " & explicitSourcePath)
for i in 1..paramCount():
  debugEcho("Argument " & $i & ": " & paramStr(i))

var
  ins = newFileStream(stdin)
  outs = newFileStream(stdout)
  gotShutdown = false
  initialized = false
  projectFiles = initTable[string, tuple[nimsuggest: NimSuggest, openFiles: int]]()
  openFiles = initTable[string, tuple[projectFile: string, fingerTable: seq[seq[tuple[u16pos, offset: int]]]]]()

template textDocumentRequest(message, kind, name, body) =
  if message["params"].isSome:
    let p = message["params"].unsafeGet
    if p.isValid(kind, allowExtra = true):
      var name = kind(p)
      body
    else:
      debugEcho("Unable to parse data as " & $kind)

proc fileuri[T](p:T):string =
  p["textDocument"]["uri"].getStr

proc filePath[T](p:T):string =
  p.fileuri[7..^1]

proc filestash[T](p:T):string =
  storage / (hash(p.fileuri).toHex & ".nim" )

proc rawLine[T](p:T):int =
  p["position"]["line"].getInt

proc rawChar[T](p:T):int =
  p["position"]["character"].getInt

proc col[T](openFiles:Table[string, tuple[projectFile: string, fingerTable: seq[seq[tuple[u16pos, offset: int]]]]];p:T):int=
  openFiles[p.fileuri].fingerTable[p.rawLine].utf16to8(p.rawChar)

template textDocumentNotification(message, kind, name, body) =
  if message["params"].isSome:
    var p = message["params"].unsafeGet
    if p.isValid(kind, allowExtra = true):
      var name = kind(p)
      body
    else:
      debugEcho("Unable to parse data as " & $kind)

proc pathToUri(path: string): string =
  # This is a modified copy of encodeUrl in the uri module. This doesn't encode
  # the / character, meaning a full file path can be passed in without breaking
  # it.
  result = newStringOfCap(path.len + path.len shr 2) # assume 12% non-alnum-chars
  for c in path:
    case c
    # https://tools.ietf.org/html/rfc3986#section-2.3
    of 'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~', '/': add(result, c)
    else:
      add(result, '%')
      add(result, toHex(ord(c), 2))

proc parseId(node: JsonNode): int =
  if node.kind == JString:
    parseInt(node.getStr)
  elif node.kind == JInt:
    node.getInt
  else:
    raise newException(MalformedFrame, "Invalid id node: " & repr(node))

proc respond(request: RequestMessage, data: JsonNode) =
  outs.sendJson create(ResponseMessage, "2.0", parseId(request["id"]), some(data), none(ResponseError)).JsonNode

proc error(request: RequestMessage, errorCode: int, message: string, data: JsonNode) =
  outs.sendJson create(ResponseMessage, "2.0", parseId(request["id"]), none(JsonNode), some(create(ResponseError, errorCode, message, data))).JsonNode

proc notify(notification: string, data: JsonNode) =
  outs.sendJson create(NotificationMessage, "2.0", notification, some(data)).JsonNode

type Certainty = enum
  None,
  Folder,
  Cfg,
  Nimble

proc getProjectFile(file: string): string =
  result = file.decodeUrl
  when defined(windows):
    result.removePrefix "/"   # ugly fix to "/C:/foo/bar" paths from "file:///C:/foo/bar"
  let (dir, _, _) = result.splitFile()
  var
    path = dir
    certainty = None
  while path.len > 0 and path != "/":
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
    if fileExists(path / current.addFileExt(".nimble")) and certainty <= Nimble:
      # Read the .nimble file and find the project file
      discard
    path = dir

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
      echo "nimlsp v", version
      quit 0
    else: 
      nimpath = expandFilename(paramStr(1))
if not fileExists(nimpath / "config/nim.cfg"):
  stderr.write "Unable to find \"config/nim.cfg\" in \"" & nimpath & "\". " &
    "Supply the Nim project folder by adding it as an argument.\n"
  quit 1

while true:
  try:
    debugEcho "Trying to read frame"
    let frame = ins.readFrame
    let msg = frame.parseJson
    if msg.isValid(RequestMessage):
      let message = RequestMessage(msg)
      debugEcho "Got valid Request message of type " & message["method"].getStr
      if not initialized and message["method"].getStr != "initialize":
        message.error(-32002, "Unable to accept requests before being initialized", newJNull())
        continue
      case message["method"].getStr:
        of "shutdown":
          debugEcho "Got shutdown request, answering"
          message.respond(newJNull())
          gotShutdown = true
        of "initialize":
          debugEcho "Got initialize request, answering"
          initialized = true
          message.respond(create(InitializeResult, create(ServerCapabilities,
            textDocumentSync = some(create(TextDocumentSyncOptions,
              openClose = some(true),
              change = some(TextDocumentSyncKind.Full.int),
              willSave = some(false),
              willSaveWaitUntil = some(false),
              save = some(create(SaveOptions, some(true)))
            )), # ?: TextDocumentSyncOptions or int or float
            hoverProvider = some(true), # ?: bool
            completionProvider = some(create(CompletionOptions,
              resolveProvider = some(true),
              triggerCharacters = some(@[".", " "])
            )), # ?: CompletionOptions
            signatureHelpProvider = none(SignatureHelpOptions),
            #signatureHelpProvider = some(create(SignatureHelpOptions,
            #  triggerCharacters = some(@["(", ","])
            #)), # ?: SignatureHelpOptions
            definitionProvider = some(true), #?: bool
            typeDefinitionProvider = none(bool), #?: bool or TextDocumentAndStaticRegistrationOptions
            implementationProvider = none(bool), #?: bool or TextDocumentAndStaticRegistrationOptions
            referencesProvider = some(true), #?: bool
            documentHighlightProvider = none(bool), #?: bool
            documentSymbolProvider = some(true), #?: bool
            workspaceSymbolProvider = none(bool), #?: bool
            codeActionProvider = none(bool), #?: bool
            codeLensProvider = none(CodeLensOptions), #?: CodeLensOptions
            documentFormattingProvider = some(false), #?: bool
            documentRangeFormattingProvider = none(bool), #?: bool
            documentOnTypeFormattingProvider = none(DocumentOnTypeFormattingOptions), #?: DocumentOnTypeFormattingOptions
            renameProvider = some(true), #?: bool
            documentLinkProvider = none(DocumentLinkOptions), #?: DocumentLinkOptions
            colorProvider = none(bool), #?: bool or ColorProviderOptions or TextDocumentAndStaticRegistrationOptions
            executeCommandProvider = none(ExecuteCommandOptions), #?: ExecuteCommandOptions
            workspace = none(WorkspaceCapability), #?: WorkspaceCapability
            experimental = none(JsonNode) #?: any
          )).JsonNode)
        of "textDocument/completion":
          message.textDocumentRequest(CompletionParams, compRequest):
            debugEcho "Running equivalent of: sug ", compRequest.filePath, ";", compRequest.filestash, ":",
              compRequest.rawLine + 1, ":",
              openFiles.col(compRequest)
            let suggestions = getNimsuggest(compRequest.fileuri).sug(compRequest.filePath, dirtyfile = compRequest.filestash,
              compRequest.rawLine + 1,
              openFiles.col(compRequest)
            )
            debugEcho "Found suggestions: ",
              suggestions[0..(if suggestions.len > 10: 10 else: suggestions.high)],
              (if suggestions.len > 10: " and " & $(suggestions.len-10) & " more" else: "")
            var completionItems = newJarray()
            for suggestion in suggestions:
              completionItems.add create(CompletionItem,
                label = suggestion.qualifiedPath[^1],
                kind = some(nimSymToLSPKind(suggestion).int),
                detail = some(nimSymDetails(suggestion)),
                documentation = some(suggestion.nimDocstring),
                deprecated = none(bool),
                preselect = none(bool),
                sortText = none(string),
                filterText = none(string),
                insertText = none(string),
                insertTextFormat = none(int),
                textEdit = none(TextEdit),
                additionalTextEdits = none(seq[TextEdit]),
                commitCharacters = none(seq[string]),
                command = none(Command),
                data = none(JsonNode)
              ).JsonNode
            message.respond completionItems
        of "textDocument/hover":
          message.textDocumentRequest(TextDocumentPositionParams, hoverRequest):
            debugEcho "Running equivalent of: def ", hoverRequest.filePath, ";", hoverRequest.filestash, ":",
              hoverRequest.rawLine + 1, ":",
              openFiles.col(hoverRequest)
            let suggestions = getNimsuggest(hoverRequest.fileuri).def(hoverRequest.filePath, dirtyfile = hoverRequest.filestash,
              hoverRequest.rawLine + 1,
              openFiles.col(hoverRequest)
            )
            debugEcho "Found suggestions: ",
              suggestions[0..(if suggestions.len > 10: 10 else: suggestions.high)],
              (if suggestions.len > 10: " and " & $(suggestions.len-10) & " more" else: "")
            if suggestions.len == 0:
              message.respond newJNull()
            else:
              var label = suggestions[0].qualifiedPath.join(".")
              if suggestions[0].forth != "":
                label &= ": " & suggestions[0].forth
              let
                rangeopt =
                  some(create(Range,
                    create(Position, hoverRequest.rawLine, hoverRequest.rawChar),
                    create(Position, hoverRequest.rawLine, hoverRequest.rawChar + suggestions[0].qualifiedPath[^1].len)
                  ))
                markedString = create(MarkedStringOption, "nim", label)
              if suggestions[0].doc != "":
                message.respond create(Hover,
                  @[
                    markedString,
                    create(MarkedStringOption, "", suggestions[0].nimDocstring),
                  ],
                  rangeopt
                ).JsonNode
              else:
                message.respond create(Hover, markedString, rangeopt).JsonNode
        of "textDocument/references":
          message.textDocumentRequest(ReferenceParams, referenceRequest):
            debugEcho "Running equivalent of: use ", referenceRequest.filePath, ";", referenceRequest.filestash, ":",
              referenceRequest.rawLine + 1, ":",
              openFiles.col(referenceRequest)
            let suggestions = getNimsuggest(referenceRequest.fileuri).use(referenceRequest.filePath, dirtyfile = referenceRequest.filestash,
              referenceRequest.rawLine + 1,
              openFiles.col(referenceRequest)
            )
            debugEcho "Found suggestions: ",
              suggestions[0..(if suggestions.len > 10: 10 else: suggestions.high)],
              (if suggestions.len > 10: " and " & $(suggestions.len-10) & " more" else: "")
            var response = newJarray()
            for suggestion in suggestions:
              if suggestion.section == ideUse or referenceRequest["context"]["includeDeclaration"].getBool:
                response.add create(Location,
                  "file://" & suggestion.filepath,
                  create(Range,
                    create(Position, suggestion.line-1, suggestion.column),
                    create(Position, suggestion.line-1, suggestion.column + suggestion.qualifiedPath[^1].len)
                  )
                ).JsonNode
            if response.len == 0:
              message.respond newJNull()
            else:
              message.respond response
        of "textDocument/rename":
          message.textDocumentRequest(RenameParams, renameRequest):
            debugEcho "Running equivalent of: use ", renameRequest.filePath, ";", renameRequest.filestash, ":",
              renameRequest.rawLine + 1, ":",
              openFiles.col(renameRequest)
            let suggestions = getNimsuggest(renameRequest.fileuri).use(renameRequest.filePath, dirtyfile = renameRequest.filestash,
              renameRequest.rawLine + 1,
              openFiles.col(renameRequest)
            )
            debugEcho "Found suggestions: ",
              suggestions[0..(if suggestions.len > 10: 10 else: suggestions.high)],
              (if suggestions.len > 10: " and " & $(suggestions.len-10) & " more" else: "")
            if suggestions.len == 0:
              message.respond newJNull()
            else:
              var textEdits = newJObject()
              for suggestion in suggestions:
                if not textEdits.hasKey("file://" & suggestion.filepath):
                  textEdits["file://" & suggestion.filepath] = newJArray()
                textEdits["file://" & suggestion.filepath].add create(TextEdit,
                  create(Range,
                    create(Position, suggestion.line-1, suggestion.column),
                    create(Position, suggestion.line-1, suggestion.column + suggestion.qualifiedPath[^1].len)
                  ),
                  renameRequest["newName"].getStr
                ).JsonNode
              message.respond create(WorkspaceEdit,
                some(textEdits),
                none(seq[TextDocumentEdit])
              ).JsonNode
        of "textDocument/definition":
          message.textDocumentRequest(TextDocumentPositionParams, definitionRequest):
            debugEcho "Running equivalent of: def ", definitionRequest.filePath, ";", definitionRequest.filestash, ":",
              definitionRequest.rawLine + 1, ":",
              openFiles.col(definitionRequest)
            let declarations = getNimsuggest(definitionRequest.fileuri).def(definitionRequest.filePath, dirtyfile = definitionRequest.filestash,
              definitionRequest.rawLine + 1,
              openFiles.col(definitionRequest)
            )
            debugEcho "Found suggestions: ",
              declarations[0..(if declarations.len > 10: 10 else: declarations.high)],
              (if declarations.len > 10: " and " & $(declarations.len-10) & " more" else: "")
            if declarations.len == 0:
              message.respond newJNull()
            else:
              var response = newJarray()
              for declaration in declarations:
                response.add create(Location,
                  "file://" & pathToUri(declaration.filepath),
                  create(Range,
                    create(Position, declaration.line-1, declaration.column),
                    create(Position, declaration.line-1, declaration.column + declaration.qualifiedPath[^1].len)
                  )
                ).JsonNode
              message.respond response
        of "textDocument/documentSymbol":
          message.textDocumentRequest(DocumentSymbolParams, symbolRequest):
            debugEcho "Running equivalent of: outline ", symbolRequest.filePath, ";", symbolRequest.filestash
            let syms = getNimsuggest(symbolRequest.fileuri).outline(symbolRequest.filePath, dirtyfile = symbolRequest.filestash)
            debugEcho "Found outlines: ",
              syms[0..(if syms.len > 10: 10 else: syms.high)],
              (if syms.len > 10: " and " & $(syms.len-10) & " more" else: "")
            if syms.len == 0:
              message.respond newJNull()
            else:
              var response = newJarray()
              for sym in syms.sortedByIt((it.line,it.column,it.quality)):
                if sym.qualifiedPath.len != 2:
                  continue
                response.add create(
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
              message.respond response
        #of "textDocument/signatureHelp":
        #  if message["params"].isSome:
        #    let signRequest = message["params"].unsafeGet
        #    whenValid(signRequest, TextDocumentPositionParams):
        #      let
        #        fileuri = signRequest["textDocument"]["uri"].getStr
        #        filestash = storage / (hash(fileuri).toHex & ".nim" )
        #      debugEcho "Got signature request for URI: ", fileuri, " copied to " & filestash
        #      let
        #        rawLine = signRequest["position"]["line"].getInt
        #        rawChar = signRequest["position"]["character"].getInt
        #        suggestions = getNimsuggest(fileuri).con(fileuri[7..^1], dirtyfile = filestash, rawLine + 1, rawChar)

        else:
          debugEcho "Unknown request"
      continue
    elif msg.isValid(NotificationMessage):
      let message = NotificationMessage(msg)
      debugEcho "Got valid Notification message of type " & message["method"].getStr
      if not initialized and message["method"].getStr != "exit":
        continue
      case message["method"].getStr:
        of "exit":
          debugEcho "Exiting"
          if gotShutdown:
            quit 0
          else:
            quit 1
        of "initialized":
          debugEcho "Properly initialized"
        of "textDocument/didOpen":
          message.textDocumentNotification(DidOpenTextDocumentParams, textDoc):
            let
              file = open(textDoc.filestash, fmWrite)
              projectFile = getProjectFile(textDoc.filePath)
            debugEcho "New document opened for URI: ", textDoc.fileuri, " \nsaving to " & textDoc.filestash
            openFiles[textDoc.fileuri] = (
              #nimsuggest: initNimsuggest(fileuri[7..^1]),
              projectFile: projectFile,
              fingerTable: @[]
            )
            if not projectFiles.hasKey(projectFile):
              debugEcho "Initialising project with project file: ", projectFile, "\nnimpath: ", nimpath
              projectFiles[projectFile] = (nimsuggest: initNimsuggest(projectFile, nimpath), openFiles: 1)
            else:
              projectFiles[projectFile].openFiles += 1
            for line in textDoc["textDocument"]["text"].getStr.splitLines:
              openFiles[textDoc.fileuri].fingerTable.add line.createUTFMapping()
              file.writeLine line
            file.close()
        of "textDocument/didChange":
          message.textDocumentNotification(DidChangeTextDocumentParams, textDoc):
            let file = open(textDoc.filestash, fmWrite)
            debugEcho "Got document change for URI: ", textDoc.fileuri, " saving to " & textDoc.filestash
            openFiles[textDoc.fileuri].fingerTable = @[]
            for line in textDoc["contentChanges"][0]["text"].getStr.splitLines:
              openFiles[textDoc.fileuri].fingerTable.add line.createUTFMapping()
              file.writeLine line
            file.close()
        of "textDocument/didClose":
          message.textDocumentNotification(DidCloseTextDocumentParams, textDoc):
            let projectFile = getProjectFile(textDoc.filePath)
            debugEcho "Got document close for URI: ", textDoc.fileuri, " copied to " & textDoc.filestash
            removeFile(textDoc.filestash)
            projectFiles[projectFile].openFiles -= 1
            if projectFiles[projectFile].openFiles == 0:
              debugEcho "Trying to stop nimsuggest"
              debugEcho "Stopped nimsuggest with code: " & $getNimsuggest(textDoc.fileuri).stopNimsuggest()
            openFiles.del(textDoc.fileuri)
        of "textDocument/didSave":
          message.textDocumentNotification(DidSaveTextDocumentParams, textDoc):
            if textDoc["text"].isSome:
              let file = open(textDoc.filestash, fmWrite)
              debugEcho "Got document save for URI: ", textDoc.fileuri, " saving to ", textDoc.filestash
              openFiles[textDoc.fileuri].fingerTable = @[]
              for line in textDoc["text"].unsafeGet.getStr.splitLines:
                openFiles[textDoc.fileuri].fingerTable.add line.createUTFMapping()
                file.writeLine line
              file.close()
            debugEcho "fileuri: ", textDoc.fileuri, ", project file: ", openFiles[textDoc.fileuri].projectFile, ", dirtyfile: ", textDoc.filestash
            let diagnostics = getNimsuggest(textDoc.fileuri).chk(textDoc.filePath, dirtyfile = textDoc.filestash)
            debugEcho "Got diagnostics: ",
              diagnostics[0..(if diagnostics.len > 10: 10 else: diagnostics.high)],
              (if diagnostics.len > 10: " and " & $(diagnostics.len-10) & " more" else: "")
            if diagnostics.len == 0:
              notify("textDocument/publishDiagnostics", create(PublishDiagnosticsParams,
                textDoc.fileuri,
                @[]).JsonNode
              )
            else:
              var response: seq[Diagnostic]
              for diagnostic in diagnostics:
                if diagnostic.line == 0:
                  continue
                if diagnostic.filePath != textDoc.filePath:
                  continue
                # Try to guess the size of the identifier
                let
                  message = diagnostic.nimDocstring
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
              notify("textDocument/publishDiagnostics", create(PublishDiagnosticsParams,
                textDoc.fileuri,
                response).JsonNode
              )
        else:
          debugEcho "Got unknown notification message"
      continue
    else:
      debugEcho "Got unknown message" & frame
  except IOError:
    break
  except CatchableError as e:
    debugEcho "Got exception: ", e.msg
    continue

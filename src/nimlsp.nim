import nimlsppkg / [base_protocol, utfmapping, nimsuggest]
include nimlsppkg / messages2
import streams
import tables
import strutils
import os
import ospaths
import hashes
include nimlsppkg / mappings

const storage = "/tmp/nimlsp"

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
# Hello Nim!
debugEcho "Started nimlsp with ENV:"
for ev in envPairs():
  debugEcho ev.key & ": " & ev.value
debugEcho "------------------------"

var
  ins = newFileStream(stdin)
  outs = newFileStream(stdout)
  gotShutdown = false
  initialized = false
  projectFiles = initTable[string, tuple[nimsuggest: NimSuggest, openFiles: int]]()
  openFiles = initTable[string, tuple[projectFile: string, fingerTable: seq[seq[tuple[u16pos, offset: int]]]]]()

template whenValid(data, kind, body) =
  if data.isValid(kind):
    var data = kind(data)
    body

template whenValid(data, kind, body, elseblock) =
  if data.isValid(kind):
    var data = kind(data)
    body
  else:
    elseblock

template textDocumentRequest(message, kind, name, body) {.dirty.} =
  if message["params"].isSome:
    let name = message["params"].unsafeGet
    whenValid(name, kind):
      let
        fileuri = name["textDocument"]["uri"].getStr
        filestash = storage / (hash(fileuri).toHex & ".nim" )
      debugEcho "Got request for URI: ", fileuri, " copied to " & filestash
      let
        rawLine = name["position"]["line"].getInt
        rawChar = name["position"]["character"].getInt
      body

template textDocumentNotification(message, kind, name, body) {.dirty.} =
  if message["params"].isSome:
    let name = message["params"].unsafeGet
    whenValid(name, kind):
      if not name["textDocument"].hasKey("languageId") or name["textDocument"]["languageId"].getStr == "nim":
        let
          fileuri = name["textDocument"]["uri"].getStr
          filestash = storage / (hash(fileuri).toHex & ".nim" )
        body

proc respond(request: RequestMessage, data: JsonNode) =
  outs.sendJson create(ResponseMessage, "2.0", request["id"].getInt, some(data), none(ResponseError)).JsonNode

proc error(request: RequestMessage, errorCode: int, message: string, data: JsonNode) =
  outs.sendJson create(ResponseMessage, "2.0", request["id"].getInt, none(JsonNode), some(create(ResponseError, errorCode, message, data))).JsonNode

proc notify(notification: string, data: JsonNode) =
  outs.sendJson create(NotificationMessage, "2.0", notification, some(data)).JsonNode

type Certainty = enum
  None,
  Folder,
  Cfg,
  Nimble

proc getProjectFile(file: string): string =
  let (dir, _, _) = file.splitFile()
  var
    path = dir
    certainty = None
  result = file
  while path.len > 0:
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

while true:
  try:
    let frame = ins.readFrame
    debugEcho frame
    let message = frame.parseJson
    whenValid(message, RequestMessage):
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
            documentSymbolProvider = none(bool), #?: bool
            workspaceSymbolProvider = none(bool), #?: bool
            codeActionProvider = none(bool), #?: bool
            codeLensProvider = none(CodeLensOptions), #?: CodeLensOptions
            documentFormattingProvider = none(bool), #?: bool
            documentRangeFormattingProvider = none(bool), #?: bool
            documentOnTypeFormattingProvider = none(DocumentOnTypeFormattingOptions), #?: DocumentOnTypeFormattingOptions
            renameProvider = none(bool), #?: bool
            documentLinkProvider = none(DocumentLinkOptions), #?: DocumentLinkOptions
            colorProvider = none(bool), #?: bool or ColorProviderOptions or TextDocumentAndStaticRegistrationOptions
            executeCommandProvider = none(ExecuteCommandOptions), #?: ExecuteCommandOptions
            workspace = none(WorkspaceCapability), #?: WorkspaceCapability
            experimental = none(JsonNode) #?: any
          )).JsonNode)
        of "textDocument/completion":
          message.textDocumentRequest(CompletionParams, compRequest):
            let suggestions = projectFiles[openFiles[fileuri].projectFile].nimsuggest.sug(fileuri[7..^1], dirtyfile = filestash,
              rawLine + 1,
              openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
            )
            debugEcho "Found suggestions: ",
              suggestions[0..(if suggestions.len > 10: 10 else: suggestions.high)],
              (if suggestions.len > 10: " and " & $(suggestions.len-10) & " more" else: "")
            var completionItems = newJarray()
            for suggestion in suggestions:
              completionItems.add create(CompletionItem,
                label = suggestion.qualifiedPath.split('.')[^1],
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
            let suggestions = projectFiles[openFiles[fileuri].projectFile].nimsuggest.def(fileuri[7..^1], dirtyfile = filestash,
              rawLine + 1,
              openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
            )
            debugEcho "Found suggestions: ",
              suggestions[0..(if suggestions.len > 10: 10 else: suggestions.high)],
              (if suggestions.len > 10: " and " & $(suggestions.len-10) & " more" else: "")
            if suggestions.len == 0:
              message.respond newJNull()
            else:
              var label = suggestions[0].qualifiedPath
              if suggestions[0].signature != "":
                label &= ": " & suggestions[0].signature
              let
                rangeopt =
                  some(create(Range,
                    create(Position, rawLine, rawChar),
                    create(Position, rawLine, rawChar)
                  ))
                markedString = create(MarkedStringOption, "nim", label)
              if suggestions[0].docstring != "\"\"":
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
            let suggestions = projectFiles[openFiles[fileuri].projectFile].nimsuggest.use(fileuri[7..^1], dirtyfile = filestash,
              rawLine + 1,
              openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
            )
            let declarations: seq[Suggestion] =
              if referenceRequest["context"]["includeDeclaration"].getBool:
                projectFiles[openFiles[fileuri].projectFile].nimsuggest.def(fileuri[7..^1], dirtyfile = filestash,
                  rawLine + 1,
                  openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
                )
              else: @[]
            debugEcho "Found suggestions: ",
              suggestions[0..(if suggestions.len > 10: 10 else: suggestions.high)],
              (if suggestions.len > 10: " and " & $(suggestions.len-10) & " more" else: "")
            if suggestions.len == 0 and declarations.len == 0:
              message.respond newJNull()
            else:
              var response = newJarray()
              for declaration in declarations:
                response.add create(Location,
                  "file://" & declaration.filepath,
                  create(Range,
                    create(Position, declaration.line-1, declaration.column),
                    create(Position, declaration.line-1, declaration.column)
                  )
                ).JsonNode
              for suggestion in suggestions:
                response.add create(Location,
                  "file://" & suggestion.filepath,
                  create(Range,
                    create(Position, suggestion.line-1, suggestion.column),
                    create(Position, suggestion.line-1, suggestion.column)
                  )
                ).JsonNode
              message.respond response
        of "textDocument/definition":
          message.textDocumentRequest(TextDocumentPositionParams, definitionRequest):
            let suggestions = projectFiles[openFiles[fileuri].projectFile].nimsuggest.def(fileuri[7..^1], dirtyfile = filestash,
              rawLine + 1,
              openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
            )
            let declarations = projectFiles[openFiles[fileuri].projectFile].nimsuggest.def(fileuri[7..^1], dirtyfile = filestash,
              rawLine + 1,
              openFiles[fileuri].fingerTable[rawLine].utf16to8(rawChar)
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
                  "file://" & declaration.filepath,
                  create(Range,
                    create(Position, declaration.line-1, declaration.column),
                    create(Position, declaration.line-1, declaration.column)
                  )
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
        #        suggestions = projectFiles[openFiles[fileuri].projectFile].nimsuggest.con(fileuri[7..^1], dirtyfile = filestash, rawLine + 1, rawChar)

        else:
          debugEcho "Unknown request"
      continue
    whenValid(message, NotificationMessage):
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
              file = open(filestash, fmWrite)
              projectFile = getProjectFile(fileuri[7..^1])
            debugEcho "New document opened for URI: ", fileuri, " saving to " & filestash
            openFiles[fileuri] = (
              #nimsuggest: startNimsuggest(fileuri[7..^1]),
              projectFile: projectFile,
              fingerTable: @[]
            )
            if not projectFiles.hasKey(projectFile):
              projectFiles[projectFile] = (nimsuggest: startNimsuggest(projectFile), openFiles: 1)
            else:
              projectFiles[projectFile].openFiles += 1
            for line in textDoc["textDocument"]["text"].getStr.splitLines:
              openFiles[fileuri].fingerTable.add line.createUTFMapping()
              file.writeLine line
            file.close()
        of "textDocument/didChange":
          message.textDocumentNotification(DidChangeTextDocumentParams, textDoc):
            let file = open(filestash, fmWrite)
            debugEcho "Got document change for URI: ", fileuri, " saving to " & filestash
            openFiles[fileuri].fingerTable = @[]
            for line in textDoc["contentChanges"][0]["text"].getStr.splitLines:
              openFiles[fileuri].fingerTable.add line.createUTFMapping()
              file.writeLine line
            file.close()
        of "textDocument/didClose":
          message.textDocumentNotification(DidCloseTextDocumentParams, textDoc):
            let projectFile = getProjectFile(fileuri[7..^1])
            debugEcho "Got document close for URI: ", fileuri, " copied to " & filestash
            removeFile(filestash)
            projectFiles[projectFile].openFiles -= 1
            if projectFiles[projectFile].openFiles == 0:
              debugEcho "Trying to stop nimsuggest"
              debugEcho "Stopped nimsuggest with code: " & $projectFiles[openFiles[fileuri].projectFile].nimsuggest.stopNimsuggest()
            openFiles.del(fileuri)
        of "textDocument/didSave":
          message.textDocumentNotification(DidSaveTextDocumentParams, textDoc):
            if textDoc["text"].isSome:
              let file = open(filestash, fmWrite)
              debugEcho "Got document change for URI: ", fileuri, " saving to ", filestash
              openFiles[fileuri].fingerTable = @[]
              for line in textDoc["text"].unsafeGet.getStr.splitLines:
                openFiles[fileuri].fingerTable.add line.createUTFMapping()
                file.writeLine line
              file.close()
            debugEcho "fileuri: ", fileuri, ", project file: ", openFiles[fileuri].projectFile, ", dirtyfile: ", filestash
            let diagnostics = projectFiles[openFiles[fileuri].projectFile].nimsuggest.chk(fileuri[7..^1], dirtyfile = filestash)
            debugEcho "Found suggestions: ",
              diagnostics[0..(if diagnostics.len > 10: 10 else: diagnostics.high)],
              (if diagnostics.len > 10: " and " & $(diagnostics.len-10) & " more" else: "")
            if diagnostics.len == 0:
              notify("textDocument/publishDiagnostics", create(PublishDiagnosticsParams,
                fileuri,
                @[]).JsonNode
              )
            else:
              var response: seq[Diagnostic]
              for diagnostic in diagnostics:
                response.add create(Diagnostic,
                  create(Range,
                    create(Position, diagnostic.line-1, diagnostic.column),
                    create(Position, diagnostic.line-1, diagnostic.column)
                  ),
                  some(case diagnostic.qualifiedPath:
                    of "Error": DiagnosticSeverity.Error.int
                    of "Hint": DiagnosticSeverity.Hint.int
                    of "Warning": DiagnosticSeverity.Warning.int
                    else: DiagnosticSeverity.Error.int),
                  none(int),
                  some("nimsuggest chk"),
                  diagnostic.nimDocstring,
                  none(seq[DiagnosticRelatedInformation])
                )
              notify("textDocument/publishDiagnostics", create(PublishDiagnosticsParams,
                fileuri,
                response).JsonNode
              )
        else:
          debugEcho "Got unknown notification message"
      continue
  except IOError:
    debugEcho "Got IOError: " & getCurrentExceptionMsg()
    break

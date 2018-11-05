import nimlsppkg / [base_protocol, utfmapping, nimsuggest]
include nimlsppkg / messages2
include nimlsppkg / mappings
import streams
import tables
import strutils
import os
import ospaths
import hashes

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

proc respond(request: RequestMessage, data: JsonNode) =
  outs.sendJson create(ResponseMessage, "2.0", request["id"].getInt, some(data), none(ResponseError)).JsonNode

proc error(request: RequestMessage, errorCode: int, message: string, data: JsonNode) =
  outs.sendJson create(ResponseMessage, "2.0", request["id"].getInt, none(JsonNode), some(create(ResponseError, errorCode, message, data))).JsonNode

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
              save = none(SaveOptions)
            )), # ?: TextDocumentSyncOptions or int or float
            hoverProvider = none(bool), # ?: bool
            completionProvider = some(create(CompletionOptions,
              resolveProvider = some(true),
              triggerCharacters = some(@["."])
            )), # ?: CompletionOptions
            signatureHelpProvider = none(SignatureHelpOptions), # ?: SignatureHelpOptions
            definitionProvider = none(bool), #?: bool
            typeDefinitionProvider = none(bool), #?: bool or TextDocumentAndStaticRegistrationOptions
            implementationProvider = none(bool), #?: bool or TextDocumentAndStaticRegistrationOptions
            referencesProvider = none(bool), #?: bool
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
          )))
        of "textDocument/completion":
          if message["params"].isSome:
            let compRequest = message["params"].unsafeGet
            whenValid(compRequest, CompletionParams):
              let
                fileuri = compRequest["textDocument"]["uri"].getStr
                filestash = storage / (hash(fileuri).toHex & ".nim" )
              debugEcho "Got completion request for URI: ", fileuri, " copied to " & filestash
              let
                rawLine = compRequest["position"]["line"].getInt
                rawChar = compRequest["position"]["character"].getInt
                suggestions = projectFiles[openFiles[fileuri].projectFile].nimsuggest.sug(fileuri[7..^1], dirtyfile = filestash,
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
                  kind = some(nimSymToLSPKind(suggestion.symKind).int),
                  detail = some(suggestion.signature),
                  documentation = some(suggestion.docstring),
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
                )
              message.respond completionItems
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
          if message["params"].isSome:
            let textDoc = message["params"].unsafeGet
            whenValid(textDoc, DidOpenTextDocumentParams):
              if textDoc["textDocument"]["languageId"].getStr == "nim":
                let
                  fileuri = textDoc["textDocument"]["uri"].getStr
                  filestash = storage / (hash(fileuri).toHex & ".nim" )
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
          if message["params"].isSome:
            let textDoc = message["params"].unsafeGet
            whenValid(textDoc, DidChangeTextDocumentParams):
              let
                fileuri = textDoc["textDocument"]["uri"].getStr
                filestash = storage / (hash(fileuri).toHex & ".nim" )
                file = open(filestash, fmWrite)
              debugEcho "Got document change for URI: ", fileuri, " saving to " & filestash
              openFiles[fileuri].fingerTable = @[]
              for line in textDoc["contentChanges"][0]["text"].getStr.splitLines:
                openFiles[fileuri].fingerTable.add line.createUTFMapping()
                file.writeLine line
              file.close()
        of "textDocument/didClose":
          if message["params"].isSome:
            let textDoc = message["params"].unsafeGet
            whenValid(textDoc, DidCloseTextDocumentParams):
              let
                fileuri = textDoc["textDocument"]["uri"].getStr
                filestash = storage / (hash(fileuri).toHex & ".nim" )
                projectFile = getProjectFile(fileuri[7..^1])
              debugEcho "Got document close for URI: ", fileuri, " copied to " & filestash
              removeFile(filestash)
              projectFiles[projectFile].openFiles -= 1
              if projectFiles[projectFile].openFiles == 0:
                debugEcho "Trying to stop nimsuggest"
                debugEcho "Stopped nimsuggest with code: " & $projectFiles[openFiles[fileuri].projectFile].nimsuggest.stopNimsuggest()
              openFiles.del(fileuri)
        else:
          debugEcho "Got unknown notification message"
      continue
  except IOError:
    debugEcho "Got IOError: " & getCurrentExceptionMsg()
    break

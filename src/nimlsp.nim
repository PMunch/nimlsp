import nimlsppkg / [baseprotocol, utfmapping, suggestlib, logger , pnode_parse]
include nimlsppkg / messages
import tables
import strutils
import os
import hashes
import uri
import algorithm
import strscans
import sets
import regex
import sequtils
import uri
import asyncfile, asyncdispatch
import streams
import segfaults

const
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

debug("Version: " & version)
debug("explicitSourcePath: " & explicitSourcePath)
for i in 1..paramCount():
  debug("Argument " & $i & ": " & paramStr(i))

type
  UriParseError* = object of Defect
    uri: string
type FileTuple = tuple[projectFile: string,  fingerTable: seq[seq[tuple[u16pos, offset: int]]],syntaxOk:bool,error:ref Exception ]
var 
  gotShutdown = false
  initialized = false
  projectFiles = initTable[string, tuple[nimsuggest: NimSuggest, openFiles: int]]()
  openFiles = initTable[string, FileTuple ]()
  projects = initHashSet[string]()
  knownDirs = initTable[string, string]() # dir and first picked file path

template textDocumentRequest(message, kind, name, body: untyped): untyped =
  if message["params"].isSome:
    let p = message["params"].unsafeGet
    if p.isValid(kind, allowExtra = true):
      var name = kind(p)
      body
    else:
      debug("Unable to parse data as " & $kind)

proc docUri[T](p:T):string =
  p["textDocument"]["uri"].getStr

proc uriToPath(uri: string): string =
  ## Convert an RFC 8089 file URI to a native, platform-specific, absolute path.
  let parsed = uri.parseUri
  if parsed.scheme != "file":
    var e = newException(UriParseError, "Invalid scheme: " & parsed.scheme & ", only \"file\" is supported")
    e.uri = uri
    raise e
  if parsed.hostname != "":
    var e = newException(UriParseError, "Invalid hostname: " & parsed.hostname & ", only empty hostname is supported")
    e.uri = uri
    raise e
  return normalizedPath(
    when defined(windows):
      parsed.path[1..^1]
    else:
      parsed.path).decodeUrl

proc filestash[T](p:T):string =
  storage / (hash(p.docUri).toHex & ".nim" )

proc rawLine[T](p:T):int =
  p["position"]["line"].getInt

proc rawChar[T](p:T):int =
  p["position"]["character"].getInt

proc col[T](openFiles:Table[string, FileTuple ];p:T):int=
  openFiles[p.docUri].fingerTable[p.rawLine].utf16to8(p.rawChar)

template textDocumentNotification(message, kind, name, body: untyped): untyped =
  if message["params"].isSome:
    var p = message["params"].unsafeGet
    if p.isValid(kind, allowExtra = true):
      var name = kind(p)
      body
    else:
      debug("Unable to parse data as " & $kind)

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



type Certainty = enum
  None,
  Folder,
  Cfg,
  Nimble

proc skipQuote(input: string; start: int; seps: set[char] = {'"'}): int =
  result = 0
  while start+result < input.len and input[start+result] in seps: inc result

proc matchSrcDir*(s: string, d: var string): bool {.inline.} =
  const p1 = """$ssrcDir$s=$s"$[skipQuote]$w"$s$[skipQuote]$s"""
  const p2 = """$ssrcdir$s=$s"$[skipQuote]$w"$s$[skipQuote]$s"""
  result = scanf(s, p1, d) or scanf(s, p2, d)

proc scanSrcDir(f: string, srcDir: var string) = 
  var fs = newFileStream(f, fmRead)
  var line = ""
  if not isNil(fs):
    while fs.readLine(line):
      if matchSrcDir(line, srcDir):
        break
    fs.close()

proc getProjectFile(file: string): string =
  result = file.decodeUrl
  when defined(windows):
    result.removePrefix "/"   # ugly fix to "/C:/foo/bar" paths from "file:///C:/foo/bar"
  let (dir, _, _) = result.splitFile()
  var
    path = dir
    certainty = None
  var srcDir:string
  var finalSrcDir:string
  if projectFiles.hasKey(result):
    return result
  while path.len > 0 and path != "/":
    if projectFiles.hasKey(result):
      return result
    let
      (dir, fname, ext) = path.splitFile()
      current = fname
    if fileExists(path / current.addFileExt(".nim")) and certainty <= Folder:
      result = path / current.addFileExt(".nim")
      certainty = Folder
    if fileExists(path / current.addFileExt(".nim")) and
      (fileExists(path / current.addFileExt(".nim.cfg")) or
      fileExists(path / current.addFileExt(".nims"))) and certainty <= Cfg:
      result = path / current.addFileExt(".nim")
      certainty = Cfg
    if knownDirs.hasKey(path):
      return knownDirs[path]
    if projectFiles.hasKey(result):
      return result
    for project in projects:
      if path.isRelativeTo(project):
        # return project
        for file in walkFiles( path / "*.nimble"):
          if certainty <= Nimble:
            # Read the .nimble file and find the project file
            # TODO interate with nimble api to find project file ,currently just string match
            let (dir, fname, ext) = file.splitFile()
            scanSrcDir(file, srcDir)
            if srcDir.len > 0:
              if fileExists(path / srcDir / fname.addFileExt(".nim")):
                finalSrcDir = path / srcDir
            elif srcDir.len == 0:
              if fileExists(path / "src" / fname.addFileExt(".nim")):
                finalSrcDir = path / "src"
            if finalSrcDir.len > 0:
              if result.isRelativeTo(finalSrcDir):
                debug "File " & result & " is relative to: " & finalSrcDir
                return finalSrcDir / fname.addFileExt(".nim")
              else:
                debug "File " & result & " is not relative to: " & finalSrcDir & " need another nimsuggest"
                if knownDirs.hasKey(result.parentDir):
                  return knownDirs[result.parentDir]
                else:
                  knownDirs[result.parentDir] = result
                return result
    path = dir

template getNimsuggest(docUri: string): Nimsuggest =
  projectFiles[openFiles[docUri].projectFile].nimsuggest

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

proc main(){.async.} =
  var frame:string
  var msg:JsonNode
  var message:RequestMessage
  var isRequest:bool
  var
    ins = newAsyncFile(stdin.getOsFileHandle().AsyncFD) #newFileStream(stdin)
    outs = newAsyncFile(stdout.getOsFileHandle().AsyncFD)#newFileStream(stdout)
    
  proc respond(request: RequestMessage, data: JsonNode) {.async.}=
    await outs.sendJson create(ResponseMessage, "2.0", parseId(request["id"]), some(data), none(ResponseError)).JsonNode

  proc error(request: RequestMessage, errorCode: int, message: string, data: JsonNode) {.async.}=
    await outs.sendJson create(ResponseMessage, "2.0", parseId(request["id"]), none(JsonNode), some(create(ResponseError, errorCode, message, data))).JsonNode

  proc sendParseError(request: RequestMessage, err: ref Exception) {.async.} = 
    # %* err.getStackTraceEntries
    await request.respond( newJNull())
    # await outs.sendJson create(ResponseMessage, "2.0", parseId(request["id"]), none(JsonNode), error =some(create(ResponseError, ParseError.ord, err.msg,data= newJNull() ))).JsonNode
    
  proc notify(notification: string, data: JsonNode){.async.} =
    await outs.sendJson create(NotificationMessage, "2.0", notification, some(data)).JsonNode
  
  template pushError(p:untyped,error: ref Exception) =
    var response: seq[Diagnostic]
    let stack = error.getStackTraceEntries
    debug "push Error stack:" & repr stack
    if stack.len > 0:
      let diagnostic = stack[0]
      response.add create(Diagnostic,
        create(Range,
          create(Position, diagnostic.line-1,0),
          create(Position, diagnostic.line-1, 0)
        ),
        some(DiagnosticSeverity.Error.int),
        none(int),
        some("compiler parser"),
        error.msg,
        none(seq[DiagnosticRelatedInformation])
      )
      await notify("textDocument/publishDiagnostics", create(PublishDiagnosticsParams,
        p.docUri,
        response).JsonNode
      )

  template syntaxCheck(request: RequestMessage,p:untyped) =
    if openFiles[p.docUri].syntaxOk == false:
      pushError(p,openFiles[p.docUri].error)
      await request.sendParseError(openFiles[p.docUri].error)
      continue
  
  while true:
    try:
      debug "Trying to read frame"
      frame = await ins.readFrame
      msg = frame.parseJson
      if msg.isValid(RequestMessage):
        isRequest = true
        message = RequestMessage(msg)
        debug "Got valid Request message of type " & message["method"].getStr
        if not initialized and message["method"].getStr != "initialize":
          await message.error(-32002, "Unable to accept requests before being initialized", newJNull())
          continue
        case message["method"].getStr:
          of "shutdown":
            debug "Got shutdown request, answering"
            await message.respond(newJNull())
            gotShutdown = true
          of "initialize":
            debug "Got initialize request, answering"
            if message["params"].unsafeGet().hasKey("workspaceFolders"):
              for p in message["params"].unsafeGet()["workspaceFolders"].getElems:
                var path = p["uri"].getStr().uriToPath 
                projects.incl(path)
            elif message["params"].unsafeGet().hasKey("rootUri"):
              var path = message["params"].unsafeGet()["rootUri"].getStr().uriToPath 
              projects.incl(path)
            initialized = true
            await message.respond(create(InitializeResult, create(ServerCapabilities,
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
              # signatureHelpProvider = none(SignatureHelpOptions),
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
            textDocumentRequest(message, CompletionParams, compRequest):
              message.syntaxCheck(compRequest)
              debug "Running equivalent of: sug ", compRequest.docUri.uriToPath, ";", compRequest.filestash, ":",
                compRequest.rawLine + 1, ":",
                openFiles.col(compRequest)
              let suggestions = getNimsuggest(compRequest.docUri).sug(compRequest.docUri.uriToPath, dirtyfile = compRequest.filestash,
                compRequest.rawLine + 1,
                openFiles.col(compRequest)
              )
              debug "Found suggestions: ",
                suggestions[0..(if suggestions.len > 10: 10 else: suggestions.high)],
                (if suggestions.len > 10: " and " & $(suggestions.len-10) & " more" else: "")
              var completionItems = newJarray()
              for suggestion in suggestions:
                completionItems.add create(CompletionItem,
                  label = suggestion.qualifiedPath[^1],
                  kind = some(nimSymToLSPKind(suggestion).int),
                  detail = some(nimSymDetails(suggestion)),
                  documentation = some(suggestion.doc),
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
              await message.respond completionItems
          of "completionItem/resolve":
            textDocumentRequest(message, CompletionItem, compRequest):
              await message.respond compRequest.JsonNode
          of "textDocument/hover":
            textDocumentRequest(message,TextDocumentPositionParams, hoverRequest):
              message.syntaxCheck(hoverRequest)
              debug "Running equivalent of: def ", hoverRequest.docUri.uriToPath, ";", hoverRequest.filestash, ":",
                hoverRequest.rawLine + 1, ":",
                openFiles.col(hoverRequest)
              debug "Project file: " & getProjectFile(hoverRequest.docUri.uriToPath)
              let suggestions = getNimsuggest(hoverRequest.docUri).def(hoverRequest.docUri.uriToPath, dirtyfile = hoverRequest.filestash,
                hoverRequest.rawLine + 1,
                openFiles.col(hoverRequest)
              )
              debug "Found suggestions: ",
                suggestions[0..(if suggestions.len > 10: 10 else: suggestions.high)],
                (if suggestions.len > 10: " and " & $(suggestions.len-10) & " more" else: "")
              if suggestions.len == 0:
                await message.respond newJNull()
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
                  await message.respond create(Hover,
                    @[
                      markedString,
                      create(MarkedStringOption, "", suggestions[0].doc),
                    ],
                    rangeopt
                  ).JsonNode
                else:
                  await message.respond create(Hover, markedString, rangeopt).JsonNode
          of "textDocument/references":
            textDocumentRequest(message,ReferenceParams, referenceRequest):
              message.syntaxCheck(referenceRequest)
              debug "Running equivalent of: use ", referenceRequest.docUri.uriToPath, ";", referenceRequest.filestash, ":",
                referenceRequest.rawLine + 1, ":",
                openFiles.col(referenceRequest)
              let suggestions = getNimsuggest(referenceRequest.docUri).use(referenceRequest.docUri.uriToPath, dirtyfile = referenceRequest.filestash,
                referenceRequest.rawLine + 1,
                openFiles.col(referenceRequest)
              )
              debug "Found suggestions: ",
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
                await message.respond newJNull()
              else:
                await message.respond response
          of "textDocument/rename":
            textDocumentRequest(message,RenameParams, renameRequest):
              message.syntaxCheck(renameRequest)
              debug "Running equivalent of: use ", renameRequest.docUri.uriToPath, ";", renameRequest.filestash, ":",
                renameRequest.rawLine + 1, ":",
                openFiles.col(renameRequest)
              let suggestions = getNimsuggest(renameRequest.docUri).use(renameRequest.docUri.uriToPath, dirtyfile = renameRequest.filestash,
                renameRequest.rawLine + 1,
                openFiles.col(renameRequest)
              )
              debug "Found suggestions: ",
                suggestions[0..(if suggestions.len > 10: 10 else: suggestions.high)],
                (if suggestions.len > 10: " and " & $(suggestions.len-10) & " more" else: "")
              if suggestions.len == 0:
                await message.respond newJNull()
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
                await message.respond create(WorkspaceEdit,
                  some(textEdits),
                  none(seq[TextDocumentEdit])
                ).JsonNode
          of "textDocument/definition":
            textDocumentRequest(message,TextDocumentPositionParams, definitionRequest):
              message.syntaxCheck(definitionRequest)
              debug "Running equivalent of: def ", definitionRequest.docUri.uriToPath, ";", definitionRequest.filestash, ":",
                definitionRequest.rawLine + 1, ":",
                openFiles.col(definitionRequest)
              let declarations = getNimsuggest(definitionRequest.docUri).def(definitionRequest.docUri.uriToPath, dirtyfile = definitionRequest.filestash,
                definitionRequest.rawLine + 1,
                openFiles.col(definitionRequest)
              )
              debug "Found suggestions: ",
                declarations[0..(if declarations.len > 10: 10 else: declarations.high)],
                (if declarations.len > 10: " and " & $(declarations.len-10) & " more" else: "")
              if declarations.len == 0:
                await message.respond newJNull()
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
                await message.respond response
          of "textDocument/documentSymbol":
            textDocumentRequest(message,DocumentSymbolParams, symbolRequest):
              message.syntaxCheck(symbolRequest)
              debug "Running equivalent of: outline ", symbolRequest.docUri.uriToPath, ";", symbolRequest.filestash
              let sugs = getNimsuggest(symbolRequest.docUri).outline(symbolRequest.docUri.uriToPath, dirtyfile = symbolRequest.filestash)
              let syms = sugs.sortedByIt((it.line,it.column,it.quality)).deduplicate(true)
              debug "Found outlines: ",
                syms[0..(if syms.len > 10: 10 else: syms.high)],
                (if syms.len > 10: " and " & $(syms.len-10) & " more" else: "")
              if syms.len == 0:
                await message.respond newJNull()
              else:
                var response = newJarray()
                for sym in syms:
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
                await message.respond response
          of "textDocument/signatureHelp":
            textDocumentRequest(message,TextDocumentPositionParams, signRequest):
              message.syntaxCheck(signRequest)
              debug "Running equivalent of: con ", signRequest.docUri.uriToPath, ";", signRequest.filestash, ":",
                signRequest.rawLine + 1, ":",
                openFiles.col(signRequest)
              let suggestions = getNimsuggest(signRequest.docUri).con(signRequest.docUri.uriToPath, dirtyfile = signRequest.filestash,
                signRequest.rawLine + 1,
                openFiles.col(signRequest)
              )
              debug "Found suggestions: ",
                suggestions[0..(if suggestions.len > 10: 10 else: suggestions.high)],
                (if suggestions.len > 10: " and " & $(suggestions.len-10) & " more" else: "")
              var signatures = newSeq[SignatureInformation]()
              for sig in suggestions:
                let label = sig.qualifiedPath[^1]
                let documentation = sig.doc
                var parameters = newSeq[ParameterInformation]()
                if sig.forth.len > 0:
                  var genericsCleanType = ""
                  var insideGeneric = 0
                  var i = 0
                  let forthLen = sig.forth.len
                  while i < forthLen:
                    if sig.forth[i] == '[':
                      inc insideGeneric
                    if insideGeneric <= 0:
                      genericsCleanType.add sig.forth[i]
                    if sig.forth[i] == ']':
                      dec insideGeneric
                    inc i
                  var m: RegexMatch
                  var signatureCutDown = genericsCleanType.find(re"(proc|macro|template|iterator|func) \((.+: .+)*\)",m)
                  if (signatureCutDown):
                    debug "signatureCutDown:",$m.group(1,genericsCleanType)
                    var params = m.group(1,genericsCleanType)[0].split(", ")
                    for label in params:
                      parameters.add create(ParameterInformation,label, none(string))
                signatures.add create(SignatureInformation,label,some(documentation),some(parameters))
              var response = create(SignatureHelp,signatures,none(int),none(int)).JsonNode # ,activeSignature,activeParameter
              await message.respond response
          else:
            debug "Unknown request"
            await message.error(errorCode = -32600,message="Unknown request:" & frame ,data = newJObject())
        continue
      elif msg.isValid(NotificationMessage):
        isRequest = false
        let message = NotificationMessage(msg)
        debug "Got valid Notification message of type " & message["method"].getStr
        if not initialized and message["method"].getStr != "exit":
          continue
        case message["method"].getStr:
          of "exit":
            debug "Exiting"
            ins.close
            outs.close
            if gotShutdown:
              quit 0
            else:
              quit 1
          of "initialized":
            debug "Properly initialized"
          of "textDocument/didOpen":
            message.textDocumentNotification(DidOpenTextDocumentParams, textDoc):
              let 
                file = open(textDoc.filestash, fmWrite)
                projectFile = getProjectFile(textDoc.docUri.uriToPath)
                text = textDoc["textDocument"]["text"].getStr
                syntax = parsePNodeStr(text,textDoc.docUri.uriToPath)
              debug "New document opened for URI: ", textDoc.docUri, " \nsaving to " & textDoc.filestash
              if not projectFiles.hasKey(projectFile):
                debug "Initialising project with project file: ", projectFile, "\nnimpath: ", nimpath
                projectFiles[projectFile] = (nimsuggest: initNimsuggest(projectFile, nimpath), openFiles: 1)
                # debug "Nimsuggest instance project path:" & projectFiles[projectFile].nimsuggest.projectPath
              else:
                projectFiles[projectFile].openFiles += 1
              var t:FileTuple = (
                projectFile: projectFile,
                fingerTable: @[],
                syntaxOk:syntax.ok,
                error:default(ref Exception)
              )
              openFiles[textDoc.docUri]  = t
              for line in text.splitLines:
                openFiles[textDoc.docUri].fingerTable.add line.createUTFMapping()
                file.writeLine line
              file.close()
          of "textDocument/didChange":
            message.textDocumentNotification(DidChangeTextDocumentParams, textDoc):
              let file = open(textDoc.filestash, fmWrite)
              debug "Got document change for URI: ", textDoc.docUri, " saving to " & textDoc.filestash
              openFiles[textDoc.docUri].fingerTable = @[]
              # If range and rangeLength are omitted, the new text is considered to be the full content of the document.
              # here we use TextDocumentSyncKind.Full when initialze
              let text = textDoc["contentChanges"][0]["text"].getStr
              let syntax = parsePNodeStr(text,textDoc.docUri.uriToPath)
              openFiles[textDoc.docUri].syntaxOk = syntax.ok
              openFiles[textDoc.docUri].error = syntax.error
              for line in text.splitLines:
                openFiles[textDoc.docUri].fingerTable.add line.createUTFMapping()
                file.writeLine line
              file.close()
          of "textDocument/didClose":
            message.textDocumentNotification(DidCloseTextDocumentParams, textDoc):
              let projectFile = getProjectFile(textDoc.docUri.uriToPath)
              debug "Got document close for URI: ", textDoc.docUri, " copied to " & textDoc.filestash
              removeFile(textDoc.filestash)
              projectFiles[projectFile].openFiles -= 1
              if projectFiles[projectFile].openFiles == 0:
                debug "Trying to stop nimsuggest"
                debug "Stopped nimsuggest with code: " & $getNimsuggest(textDoc.docUri).stopNimsuggest()
              openFiles.del(textDoc.docUri)
          of "textDocument/didSave":
            message.textDocumentNotification(DidSaveTextDocumentParams, textDoc):
              if textDoc["text"].isSome:
                let file = open(textDoc.filestash, fmWrite)
                debug "Got document save for URI: ", textDoc.docUri, " saving to ", textDoc.filestash
                openFiles[textDoc.docUri].fingerTable = @[]
                let text = textDoc["text"].unsafeGet.getStr
                let syntax = parsePNodeStr(text,textDoc.docUri.uriToPath)
                openFiles[textDoc.docUri].syntaxOk = syntax.ok
                openFiles[textDoc.docUri].error = syntax.error
                for line in text.splitLines:
                  openFiles[textDoc.docUri].fingerTable.add line.createUTFMapping()
                  file.writeLine line
                file.close()
                if not syntax.ok:
                  pushError(textDoc,syntax.error)
                  continue
              debug "docUri: ", textDoc.docUri, ", project file: ", openFiles[textDoc.docUri].projectFile, ", dirtyfile: ", textDoc.filestash
              let diagnostics = getNimsuggest(textDoc.docUri).chk(textDoc.docUri.uriToPath, dirtyfile = textDoc.filestash)
              debug "Got diagnostics: ",
                diagnostics[0..(if diagnostics.len > 10: 10 else: diagnostics.high)],
                (if diagnostics.len > 10: " and " & $(diagnostics.len-10) & " more" else: "")
              if diagnostics.len == 0:
                await notify("textDocument/publishDiagnostics", create(PublishDiagnosticsParams,
                  textDoc.docUri,
                  @[]).JsonNode
                )
              else:
                var response: seq[Diagnostic]
                for diagnostic in diagnostics:
                  if diagnostic.line == 0:
                    continue
                  if diagnostic.filepath != textDoc.docUri.uriToPath:
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
                await notify("textDocument/publishDiagnostics", create(PublishDiagnosticsParams,
                  textDoc.docUri,
                  response).JsonNode
                )
          of "$/cancelRequest":
            message.textDocumentNotification(CancelParams, cancelParams):
              await outs.sendJson create(ResponseMessage, "2.0", parseId(cancelParams["id"]), some(newJObject()), none(ResponseError)).JsonNode
          else:
            debug "Got unknown notification message"
        continue
      else:
        debug "Got unknown message" & frame
    except JsonParsingError as e:
      debug "Got exception parsing json: ", e.msg & frame.substr(0, 100)
    except UriParseError as e:
      debug "Got exception parsing URI: ", e.msg
      continue
    except IOError as e:
      debug "Got exception IOError: ", e.msg
      break
    except CatchableError as e:
      debug "Got exception CatchableError: ", e.msg
      continue
    except NilAccessDefect as e:
      debug "Got exception NilAccessDefect: ", e.msg , $ e.getStackTraceEntries
      continue
waitFor main()
import nimlsppkg / base_protocol
include nimlsppkg / messages2
import streams
when defined(debugLogging):
  import strutils

template debugEcho(args: varargs[string, `$`]) =
  when defined(debugLogging):
    stderr.write(join args)
    stderr.write("\n")
# Hello Nim!
debugEcho "Hello, World v4!"

var
  ins = newFileStream(stdin)
  outs = newFileStream(stdout)
  gotShutdown = false
  initialized = false

template whenValid(data, kind, body) =
  if data.isValid(kind):
    var data = kind(data)
    body

proc respond(request: RequestMessage, data: JsonNode) =
  outs.sendJson create(ResponseMessage, "2.0", request["id"].getInt, some(data), none(ResponseError)).JsonNode

proc error(request: RequestMessage, errorCode: int, message: string, data: JsonNode) =
  outs.sendJson create(ResponseMessage, "2.0", request["id"].getInt, none(JsonNode), some(create(ResponseError, errorCode, message, data))).JsonNode

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
          message.respond(create(InitializeResult, create(ServerCapabilities,
            textDocumentSync = none(TextDocumentSyncOptions), # ?: TextDocumentSyncOptions or int or float
            hoverProvider = none(bool), # ?: bool
            completionProvider = none(CompletionOptions), # ?: CompletionOptions
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
        else:
          debugEcho "Unknown request"
      continue
    whenValid(message, NotificationMessage):
      if not initialized and message["method"].getStr != "exit":
        continue
      case message["method"].getStr:
        of "exit":
          if gotShutdown:
            quit 0
          else:
            quit 1
        of "initialized":
          initialized = true
        else:
          debugEcho "Got unknown notification message"
      continue
  except IOError:
    break

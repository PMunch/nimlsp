import unittest
import std/[asyncdispatch, asyncfile, os, osproc, options, json]
import .. / src / nimlsppkg / baseprotocol
include .. / src / nimlsppkg / messages

let
  nimlsp = parentDir(parentDir(currentSourcePath())) / "nimlsp"
  p = startProcess(nimlsp, options = {})
  i = newAsyncFile(p.inputHandle().AsyncFD)
  o = newAsyncFile(p.outputHandle().AsyncFD)

suite "Nim LSP basic operation":
  test "Nim LSP can be initialised":
    var ir = create(RequestMessage, "2.0", 0, "initialize", some(
      create(InitializeParams,
        processId = getCurrentProcessId(),
        rootPath = none(string),
        rootUri = "file:///tmp/",
        initializationOptions = none(JsonNode),
        capabilities = create(ClientCapabilities,
          workspace = none(WorkspaceClientCapabilities),
          textDocument = none(TextDocumentClientCapabilities),
          experimental = none(JsonNode)
        ),
        trace = none(string),
        workspaceFolders = none(seq[WorkspaceFolder])
      ).JsonNode)
    ).JsonNode
    waitFor i.sendJson ir

    var frame = o.readFrame
    var message = parseJson waitFor frame
    if message.isValid(ResponseMessage):
      var data = ResponseMessage(message)
      check data["id"].getInt == 0
      echo data["result"]
    else:
      check false

    echo message

p.terminate()

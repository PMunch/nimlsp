import std/[unittest, asyncdispatch, asyncfile, os, options, json, strutils, streams]
import .. / src / nimlsppkg / baseprotocol
include .. / src / nimlsppkg / messages
import pkg/asynctools

let
  nimlsp = parentDir(parentDir(currentSourcePath())) / "nimlsp"
  p = startProcess(nimlsp, options = {})

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
    var frame = newString(1024)
    var d = formFrame(ir)
    discard waitFor p.inputHandle().write(cast[pointer](d[0].addr), d.len)
    let n = waitFor p.outputHandle().readInto(frame[0].addr, 1024)

    var message = parseJson frame.split("\r\n\r\n")[1]
    if message.isValid(ResponseMessage):
      var data = ResponseMessage(message)
      check data["id"].getInt == 0
      echo data["result"]
    else:
      check false

    echo message

p.terminate()

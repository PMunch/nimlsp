import nimlsppkg / base_protocol
include nimlsppkg / messages2
import streams
# Hello Nim!
stderr.write "Hello, World v4!\n"


var
  ins = newFileStream(stdin)
  outs = newFileStream(stdout)
  gotShutdown = false

template whenValid(data, kind, body) =
  if data.isValid(kind):
    var data = kind(data)
    body

while true:
  try:
    let frame = ins.readFrame
    stderr.write frame
    stderr.write "\n"
    let jsonData = frame.parseJson
    whenValid(jsonData, RequestMessage):
      stderr.write "Got valid Request message "
      stderr.write "of type " & jsonData["method"].getStr & "\n"
      if jsonData["method"].getStr == "shutdown":
        stderr.write "Got shutdown request, answering\n"
        outs.sendJson create(ResponseMessage, "2.0", jsonData["id"].getInt, some(newJNull()), none(ResponseError)).JsonNode
        gotShutdown = true
    whenValid(jsonData, NotificationMessage):
      if jsonData["method"].getStr == "exit":
        if gotShutdown:
          quit 0
        else:
          quit 1
      else:
        stderr.write "Got unknown notification message\n"
  except IOError:
    break

import std/[asyncdispatch, asyncfile, json, parseutils, streams, strformat,
            strutils]


type
  BaseProtocolError* = object of Defect

  MalformedFrame* = object of BaseProtocolError
  UnsupportedEncoding* = object of BaseProtocolError

proc skipWhitespace(x: string, pos: int): int =
  result = pos
  while result < x.len and x[result] in Whitespace:
    inc result

proc sendFrame*(s: Stream | AsyncFile, frame: string) {.multisync} =
  when defined(debugCommunication):
    infoLog(frame)
  let content = &"Content-Length: {frame.len}\r\n\r\n{frame}"
  when s is Stream:
    s.write content
    s.flush
  else:
    await s.write content

proc formFrame*(data: JsonNode): string = 
  var frame = newStringOfCap(1024)
  toUgly(frame, data)
  result = &"Content-Length: {frame.len}\r\n\r\n{frame}"

proc sendJson*(s: Stream | AsyncFile, data: JsonNode) {.multisync.} =
  var frame = newStringOfCap(1024)
  toUgly(frame, data)
  when s is Stream:
    s.sendFrame(frame)
  else:
    await s.sendFrame(frame)

proc readFrame*(s: Stream | AsyncFile): Future[string] {.multisync.} =
  var contentLen = -1
  var headerStarted = false
  var ln: string
  while true:
    when s is Stream:
      ln = s.readLine()
    else:
      ln = await s.readLine()
    if ln.len != 0:
      headerStarted = true
      let sep = ln.find(':')
      if sep == -1:
        raise newException(MalformedFrame, "invalid header line: " & ln)

      let valueStart = ln.skipWhitespace(sep + 1)

      case ln[0 ..< sep]
      of "Content-Type":
        if ln.find("utf-8", valueStart) == -1 and ln.find("utf8", valueStart) == -1:
          raise newException(UnsupportedEncoding, "only utf-8 is supported")
      of "Content-Length":
        if parseInt(ln, contentLen, valueStart) == 0:
          raise newException(MalformedFrame, "invalid Content-Length: " &
                                              ln.substr(valueStart))
      else:
        # Unrecognized headers are ignored
        discard
    elif not headerStarted:
      continue
    else:
      if contentLen != -1:
        when s is Stream:
          var buf = s.readStr(contentLen)
        else:
          var buf = newString(contentLen)
          discard await s.readBuffer(buf[0].addr, contentLen)
        when defined(debugCommunication):
          infoLog(buf)
        return buf
      else:
        raise newException(MalformedFrame, "missing Content-Length header")


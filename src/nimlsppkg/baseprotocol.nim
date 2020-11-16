import streams, strutils, parseutils, json

type
  BaseProtocolError* = object of Defect

  MalformedFrame* = object of BaseProtocolError
  UnsupportedEncoding* = object of BaseProtocolError

proc skipWhitespace(x: string, pos: int): int =
  result = pos
  while result < x.len and x[result] in Whitespace:
    inc result

proc sendFrame*(s: Stream, frame: string) =
  when defined(debugCommunication):
    stderr.write(frame)
    stderr.write("\n")
  s.write "Content-Length: " & $frame.len & "\r\n\r\n" & frame
  s.flush

proc sendJson*(s: Stream, data: JsonNode) =
  var frame = newStringOfCap(1024)
  toUgly(frame, data)
  s.sendFrame(frame)

proc readFrame*(s: Stream): TaintedString =
  var contentLen = -1
  var headerStarted = false

  while true:
    var ln = string s.readLine()

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
        when defined(debugCommunication):
          let msg = s.readStr(contentLen)
          stderr.write(msg.substr(0, 200))
          stderr.write("\n")
          return msg
        else:
          return s.readStr(contentLen)
      else:
        raise newException(MalformedFrame, "missing Content-Length header")


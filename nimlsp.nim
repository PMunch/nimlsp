import packedjson

type
  ResponseError = distinct JsonNode
  MessageKind = enum
    Notification, Request
  Message = object
    case kind*: MessageKind:
      of Notification: notification: JsonNode
      of Request: request: JsonNode
  NotificationMessage = distinct JsonNode
  ResponseMessage = distinct JsonNode
  ErrorCode = enum
    RequestCancelled = -32800 # All the other error codes are from JSON-RPC
    ParseError = -32700,
    InternalError = -32603,
    InvalidParams = -32602,
    MethodNotFound = -32601,
    InvalidRequest = -32600,
    ServerErrorStart = -32099,
    ServerNotInitialized = -32002,
    ServerErrorEnd = -32000,

proc createResponse(id: int, res: JsonNode = newJNull(), error: ResponseError = newJNull().ResponseError): JsonTree =
  result = %*{
    "id": id
  }
  if res.kind != JNull:
    result["result"] = res
  if error.JsonNode.kind != JNull:
    result["error"] = error.JsonNode

proc createError(code: ErrorCode, message: string, data: JsonNode = newJNull()): ResponseError =
  result = ResponseError(%*{
    "code": ord code,
    "message": message
  })
  if data.kind != JNull:
    result.JsonTree["data"] = data

proc readMessage(json: string): Message =
  var parsedJson = parseJson(json)
  doAssert parsedJson.hasKey("jsonrpc"), "JSON is missing jsonrpc key"
  doAssert parsedJson["jsonrpc"].getStr == "2.0", "Wrong JSON-RPC version"
  doAssert parsedJson.hasKey("method"), "JSON-RPC message missing method"
  doAssert parsedJson["method"].kind == JString, "Field \"method\" in JSON-RPC has incorrect type"
  if parsedJson.hasKey("id"):
    doAssert parsedJson["id"].kind in {JString, JFloat, JInt}, "Field \"id\" in JSON-RPC has incorrect type"
    if parsedJson.hasKey("params"):
      doAssert parsedJson.len == 4, "Too many fields in JSON-RPC message"
      doAssert parsedJson["params"].kind in {JArray, JObject}, "Field \"params\" in JSON-RPC has incorrect type"
    else:
      doAssert parsedJson.len == 3, "Too many fields in JSON-RPC message"
    return Message(kind: Request, request: parsedJson)
  else:
    doAssert (parsedJson.hasKey("params") and parsedJson.len == 3) or (not parsedJson.hasKey("params") and parsedJson.len == 2), "Too many fields in JSON-RPC message"
    return Message(kind: Notification, notification: parsedJson)



echo createResponse(100, error = createError(ParseError, "Hello world"))
echo readMessage("""
{
  "jsonrpc": "2.0",
  "id": 100,
  "method": "something",
}
""")

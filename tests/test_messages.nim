import unittest
import nimlsppkg / messages
import packedjson

let message = "Hello World"

suite "createError()":
    test "Generate a parse error message":
        let error = JsonNode(createError(ParseError, message))
        check(getInt(error["code"]) == ord(ParseError))
        check(getStr(error["message"]) == message)

suite "createResponse()":
    test "Generate a response":
        let res = createResponse(100, %*{ "result": "Success" })
        check(getStr(res["result"]["result"]) == "Success")
    test "Generate an error response":
        let response = createResponse(101, error = createError(ParseError, message))
        check(getInt(response["id"]) == 101)
        check(getInt(response["error"]["code"]) == ord(ParseError))


suite "readMessage()":
    const messageRequest = """{
        "jsonrpc": "2.0",
        "id": 100,
        "method": "something",
    }"""
    const messageNotification = """{
        "jsonrpc": "2.0",
        "method": "something",
    }"""
    test "Generate Request Message":
        let message = readMessage(messageRequest)
        check(message.kind == Request)
    test "Generate Notification Message":
        let message = readMessage(messageNotification)
        check(message.kind == Notification)

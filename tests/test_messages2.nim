import unittest
include nimlsppkg / messages3
#import packedjson

let message = "Hello World"

suite "Create ResponseError":
    test "Generate a parse error message":
        let error = JsonNode(create(ResponseError, ParseError.ord, message, newJNull()))
        check(getInt(error["code"]) == ord(ParseError))
        check(getStr(error["message"]) == message)

suite "Create ResponseMessage":
    test "Generate a response":
        let res = create(ResponseMessage, "2.0", 100, some(%*{ "result": "Success" }), none(ResponseError))
        echo res
        check(getStr(res["result"]["result"]) == "Success")
    test "Generate an error response":
        let response = create(ResponseMessage, "2.0", 101, none(JsonNode), some(create(ResponseError, ParseError.ord, message, newJNull())))
        check(getInt(response["id"]) == 101)
        check(getInt(response["error"]["code"]) == ord(ParseError))


#[
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
        ]#

import unittest
include nimlsppkg / messages2
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
        check(getStr(res["result"]["result"]) == "Success")
    test "Generate an error response":
        let response = create(ResponseMessage, "2.0", 101, none(JsonNode), some(create(ResponseError, ParseError.ord, message, newJNull())))
        check(getInt(response["id"]) == 101)
        check(getInt(response["error"]["code"]) == ord(ParseError))

suite "Read RequestMessage":
    const requestMessage = """{
        "jsonrpc": "2.0",
        "id": 100,
        "method": "something",
    }"""
    const notificationMessage = """{
        "jsonrpc": "2.0",
        "method": "something",
    }"""
    test "Verify RequestMessage":
        check(parseJson(requestMessage).isValid(RequestMessage))
    test "Verify NotificationMessage":
        check(parseJson(notificationMessage).isValid(NotificationMessage))


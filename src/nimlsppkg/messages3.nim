type
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

# Anything below here comes from the LSP specification
import jsonschema
import json
import options
import sequtils

jsonSchema:
  Message:
    jsonrpc: string

  RequestMessage extends Message:
    id: int or float or string
    "method": string
    params?: any[] or any

  ResponseMessage extends Message:
    id: int or float or string or nil
    "result"?: any
    error?: ResponseError

  ResponseError:
    code: int or float
    message: string
    data: any

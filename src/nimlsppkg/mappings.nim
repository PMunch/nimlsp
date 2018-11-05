func nimSymToLSPKind(kind: string): CompletionItemKind =
  case kind:
  of "skConst": CompletionItemKind.Value
  of "skEnumField": CompletionItemKind.Enum
  of "skForVar": CompletionItemKind.Variable
  of "skIterator": CompletionItemKind.Keyword
  of "skLabel": CompletionItemKind.Keyword
  of "skLet": CompletionItemKind.Value
  of "skMacro": CompletionItemKind.Snippet
  of "skMethod": CompletionItemKind.Method
  of "skParam": CompletionItemKind.Variable
  of "skProc": CompletionItemKind.Function
  of "skResult": CompletionItemKind.Value
  of "skTemplate": CompletionItemKind.Snippet
  of "skType": CompletionItemKind.Class
  of "skVar": CompletionItemKind.Field
  of "skFunc": CompletionItemKind.Function
  else: CompletionItemKind.Property

func nimSymDetails(suggest: Suggestion): string =
  case suggest.symKind:
  of "skConst": "const " & suggest.qualifiedPath & ": " & suggest.signature
  of "skEnumField": "enum " & suggest.signature
  of "skForVar": "for var of " & suggest.signature
  of "skIterator": suggest.signature
  of "skLabel": "label"
  of "skLet": "let of " & suggest.signature
  of "skMacro": "macro"
  of "skMethod": suggest.signature
  of "skParam": "param"
  of "skProc": suggest.signature
  of "skResult": "result"
  of "skTemplate": suggest.signature
  of "skType": "type " & suggest.qualifiedPath
  of "skVar": "var of " & suggest.signature
  else: suggest.signature

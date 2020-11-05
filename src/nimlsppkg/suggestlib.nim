import macros, os

const explicitSourcePath {.strdefine.} = getCurrentCompilerExe().parentDir.parentDir

macro mImport(path: static[string]): untyped =
  result = newNimNode(nnkStmtList)
  result.add(quote do:
    import `path`
  )

mImport(explicitSourcePath / "nimsuggest" / "nimsuggest.nim")
import messageenums
import strutils
import compiler / ast
export Suggest
export IdeCmd
export NimSuggest
export initNimSuggest

proc stopNimSuggest*(nimsuggest: NimSuggest): int = 42

proc `$`*(suggestion: Suggest): string =
  let sep = ", "
  result = "(section: " & $suggestion.section
  result.add sep
  result.add "symKind: " & $suggestion.symkind.TSymKind
  result.add sep
  result.add "qualifiedPath: " & suggestion.qualifiedPath.join(".")
  result.add sep
  result.add "forth: " & suggestion.forth
  result.add sep
  result.add "filePath: " & suggestion.filePath
  result.add sep
  result.add "line: " & $suggestion.line
  result.add sep
  result.add "column: " & $suggestion.column
  result.add sep
  result.add "doc: " & $suggestion.doc
  result.add sep
  result.add "quality: " & $suggestion.quality
  result.add sep
  result.add "line: " & $suggestion.line
  result.add sep
  result.add "prefix: " & $suggestion.prefix
  result.add ")"

func nimSymToLSPKind*(suggest: Suggest): CompletionItemKind =
  case $suggest.symKind.TSymKind:
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

func nimSymToLSPKind*(suggest: byte): SymbolKind =
  case $TSymKind(suggest):
  of "skConst": SymbolKind.Constant
  of "skEnumField": SymbolKind.EnumMember
  of "skIterator": SymbolKind.Function
  of "skConverter": SymbolKind.Function
  of "skLet": SymbolKind.Variable
  of "skMacro": SymbolKind.Function
  of "skMethod": SymbolKind.Method
  of "skProc": SymbolKind.Function
  of "skTemplate": SymbolKind.Function
  of "skType": SymbolKind.Class
  of "skVar": SymbolKind.Variable
  of "skFunc": SymbolKind.Function
  else: SymbolKind.Function

func nimSymDetails*(suggest: Suggest): string =
  case $suggest.symKind.TSymKind:
  of "skConst": "const " & suggest.qualifiedPath.join(".") & ": " & suggest.forth
  of "skEnumField": "enum " & suggest.forth
  of "skForVar": "for var of " & suggest.forth
  of "skIterator": suggest.forth
  of "skLabel": "label"
  of "skLet": "let of " & suggest.forth
  of "skMacro": "macro"
  of "skMethod": suggest.forth
  of "skParam": "param"
  of "skProc": suggest.forth
  of "skResult": "result"
  of "skTemplate": suggest.forth
  of "skType": "type " & suggest.qualifiedPath.join(".")
  of "skVar": "var of " & suggest.forth
  else: suggest.forth

func nimDocstring*(suggest: Suggest): string =
  suggest.doc

macro createCommands(fileOnly:static[bool] = false, commands: varargs[untyped]) =
  result = nnkStmtList.newTree
  for cmd in commands:
    let cmdStr = cmd.strVal
    var params = nnkFormalParams.newTree(
        nnkBracketExpr.newTree(
          newIdentNode("seq"),
          newIdentNode("Suggest")
        ),
        nnkIdentDefs.newTree(
          newIdentNode("nimsuggest"),
          newIdentNode("NimSuggest"),
          newEmptyNode()
        ),
        nnkIdentDefs.newTree(
          newIdentNode("file"),
          newIdentNode("string"),
          newEmptyNode()
        ),
        nnkIdentDefs.newTree(
          newIdentNode("dirtyfile"),
          newEmptyNode(),
          newLit("")
        ),
       
      )
    if not fileOnly:
      params.add nnkIdentDefs.newTree(
          newIdentNode("line"),
          newIdentNode("int"),
          newEmptyNode()
        )
      params.add nnkIdentDefs.newTree(
          newIdentNode("col"),
          newIdentNode("int"),
          newEmptyNode()
        )
    var call = nnkCall.newTree(
      nnkDotExpr.newTree(
        newIdentNode("nimsuggest"),
        newIdentNode("runCmd")
      ),
      ident("ide" & cmdStr)
      ,
      nnkCommand.newTree(
        newIdentNode("AbsoluteFile"),
        newIdentNode("file")
      ),
      nnkCommand.newTree(
        newIdentNode("AbsoluteFile"),
        newIdentNode("dirtyfile")
      )
    )
    if not fileOnly:
      call.add newIdentNode("line")
      call.add newIdentNode("col")
    else:
      call.add newLit(0)
      call.add newLit(0)
    result.add nnkStmtList.newTree(
    nnkProcDef.newTree(
      nnkPostfix.newTree(
        newIdentNode("*"),
        newIdentNode(cmdStr)
      ),
      newEmptyNode(),
      newEmptyNode(),
      params,
      newEmptyNode(),
      newEmptyNode(),
      nnkStmtList.newTree(
       call
        )
      )
    )

createCommands(false,sug,con,def,use,dus)
createCommands(true,chk,highlight,outline,known)

when isMainModule:
  var graph = initNimSuggest(currentSourcePath, nimPath = getCurrentCompilerExe().parentDir.parentDir)
  var suggestions = graph.sug(currentSourcePath, currentSourcePath, 184, 26)
  echo "Got ", suggestions.len, " suggestions"
  for suggestion in suggestions:
    echo suggestion

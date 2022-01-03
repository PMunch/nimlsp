import macros, os
import logger

const explicitSourcePath {.strdefine.} = getCurrentCompilerExe().parentDir.parentDir

macro mImport(path: static[string]): untyped =
  result = nnkImportStmt.newTree(newLit(path))

mImport(explicitSourcePath / "nimsuggest" / "nimsuggest.nim")
import messageenums
import strutils
import compiler / ast
export Suggest
export IdeCmd
export NimSuggest
export initNimSuggest
# export projectPath

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
  result.add "prefix: " & $suggestion.prefix
  result.add ")"

proc `==`*(a,b: Suggest): bool =
  result = a.filePath == b.filePath and a.line == b.line and a.column == b.column and a.qualifiedPath == b.qualifiedPath and a.section == b.section
func collapseByIdentifier*(suggestion: Suggest): string =
  ## Function to create an identifier that can be used to remove duplicates in a list
  suggestion.qualifiedPath[^1] & "__" & $suggestion.symKind.TSymKind

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

macro createCommands(fileOnly:static[bool] = false, commands: varargs[untyped]) =
  result = nnkStmtList.newTree
  for cmd in commands:
    let cmdStr = cmd.strVal
    var params = nnkFormalParams.newTree(
        nnkBracketExpr.newTree(
          ident("seq"),
          ident"Suggest"
        ),
        nnkIdentDefs.newTree(
          ident("nimsuggest"),
          ident("NimSuggest"),
          newEmptyNode()
        ),
        nnkIdentDefs.newTree(
          ident("file"),
          ident("string"),
          newEmptyNode()
        ),
        nnkIdentDefs.newTree(
          ident("dirtyfile"),
          newEmptyNode(),
          newLit("")
        ),
       
      )
    if not fileOnly:
      params.add nnkIdentDefs.newTree(
          ident("line"),
          ident("int"),
          newEmptyNode()
        )
      params.add nnkIdentDefs.newTree(
          ident("col"),
          ident("int"),
          newEmptyNode()
        )
    var call = nnkCall.newTree(
      nnkDotExpr.newTree(
        ident("nimsuggest"),
        ident("runCmd")
      ),
      ident("ide" & cmdStr)
      ,
      nnkCommand.newTree(
        ident("AbsoluteFile"),
        ident("file")
      ),
      nnkCommand.newTree(
        ident("AbsoluteFile"),
        ident("dirtyfile")
      )
    )
    if not fileOnly:
      call.add ident("line")
      call.add ident("col")
    else:
      call.add newLit(0)
      call.add newLit(0)
    var tryCatch = nnkTryStmt.newTree(
      nnkStmtList.newTree(
        nnkAsgn.newTree(
          newIdentNode("result"),
          call
        )
      ),
      nnkExceptBranch.newTree(
        nnkInfix.newTree(
          newIdentNode("as"),
          newIdentNode("Exception"),
          newIdentNode("e")
        ),
        nnkStmtList.newTree(
          nnkCommand.newTree(
            newIdentNode("debug"),
            nnkPrefix.newTree(
              newIdentNode("$"),
              nnkCall.newTree(
                newIdentNode("getStackTraceEntries")
              )
            )
          )
        )
      )
    )
    result.add nnkStmtList.newTree(
    nnkProcDef.newTree(
      nnkPostfix.newTree(
        ident("*"),
        ident(cmdStr)
      ),
      newEmptyNode(),
      newEmptyNode(),
      params,
      newEmptyNode(),
      newEmptyNode(),
      nnkStmtList.newTree(
       tryCatch
        )
      )
    )

createCommands(false,sug,con,def,use,dus,none)
createCommands(true,chk,highlight,outline,known)

proc `mod`*(nimsuggest: NimSuggest, file: string, dirtyfile = ""): seq[Suggest] =
  nimsuggest.runCmd(ideMod, AbsoluteFile file, AbsoluteFile dirtyfile, 0, 0)

when isMainModule:
  var graph = initNimSuggest(currentSourcePath, nimPath = getCurrentCompilerExe().parentDir.parentDir)
  var suggestions = graph.sug(currentSourcePath, currentSourcePath, 206, 26)
  echo "Got ", suggestions.len, " suggestions"
  for suggestion in suggestions:
    echo suggestion

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
  result.add suggestion.forth
  result.add sep
  result.add suggestion.filePath
  result.add sep
  result.add $suggestion.line
  result.add sep
  result.add $suggestion.column
  result.add sep
  result.add $suggestion.quality
  result.add sep
  result.add $suggestion.line
  result.add sep
  result.add $suggestion.prefix

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

template createFullCommand(command: untyped) {.dirty.} =
  proc command*(nimsuggest: NimSuggest, file: string, dirtyfile = "",
            line: int, col: int): seq[Suggest] =
    nimsuggest.runCmd(`ide command`, AbsoluteFile file, AbsoluteFile dirtyfile, line, col)

template createFileOnlyCommand(command: untyped) {.dirty.} =
  proc command*(nimsuggest: NimSuggest, file: string, dirtyfile = ""): seq[Suggest] =
    nimsuggest.runCmd(`ide command`, AbsoluteFile file, AbsoluteFile dirtyfile, 0, 0)

createFullCommand(sug)
createFullCommand(con)
createFullCommand(def)
createFullCommand(use)
createFullCommand(dus)
createFileOnlyCommand(chk)
#createFileOnlyCommand(`mod`)
createFileOnlyCommand(highlight)
createFileOnlyCommand(outline)
createFileOnlyCommand(known)

when isMainModule:
  var graph = initNimSuggest("/home/peter/div/nimlsp/suglibtest.nim", nimPath = "/home/peter/div/Nim")
  var suggestions = graph.sug("/home/peter/div/nimlsp/suglibtest.nim", "/home/peter/div/nimlsp/suglibtest.nim", 7, 2)
  echo "Got ", suggestions.len, " suggestions"
  for suggestion in suggestions:
    echo suggestion

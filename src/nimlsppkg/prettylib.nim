import macros, os

const explicitSourcePath {.strdefine.} = getCurrentCompilerExe().parentDir.parentDir

macro mImport(path: static[string]): untyped =
  result = newNimNode(nnkStmtList)
  result.add(quote do:
    import `path`
  )

mImport(explicitSourcePath / "nimpretty" / "nimpretty.nim")
export PrettyOptions

proc prettyPrintFile*(infile, outfile: string, opt: PrettyOptions) =
  prettyPrint(infile, outfile, opt)

when isMainModule:
  var opt = PrettyOptions(indWidth: 2, maxLineLen: 80)
  prettyPrintFile(currentSourcePath, currentSourcePath, opt)


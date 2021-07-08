
from os import nil
import macros, os

const explicitSourcePath {.strdefine.} = getCurrentCompilerExe().parentDir.parentDir

macro mImport(path: static[string]): untyped =
  result = nnkImportStmt.newTree(newLit(path))

mImport(os.joinPath( "compiler" , "parser.nim"))
mImport(os.joinPath( "compiler" , "llstream.nim"))
mImport(os.joinPath( "compiler" , "idents.nim"))
mImport(os.joinPath( "compiler" , "options.nim"))
mImport(os.joinPath( "compiler" , "pathutils.nim"))
mImport(os.joinPath( "compiler" , "lineinfos.nim"))
mImport(os.joinPath( "compiler" , "ast.nim"))

type ParseError = ref object of CatchableError
const DevNullDir = when defined(windows):"c:\\" else: "/dev"
const DevNullFile = when defined(windows):"nul" else: "null"

proc parsePNodeStr*(str: string, filePath:string): tuple[ok:bool,error:ref Exception] =
  result.ok = true
  let cache: IdentCache = newIdentCache()
  let config: ConfigRef = newConfigRef()
  var pars: Parser
  pars.lex.errorHandler =
    proc(conf: ConfigRef; info: TLineInfo; msg: TMsgKind; arg: string) =
      if msg notin {hintLineTooLong}:
        raise ParseError(msg: arg)

  config.verbosity = 0
  config.options.excl optHints
  when defined(nimpretty):
    config.outDir = toAbsoluteDir(DevNullDir)
    config.outFile = RelativeFile(DevNullFile)
  try:
    openParser(
      p = pars,
      filename = AbsoluteFile(filePath),
      inputStream = llStreamOpen(str),
      cache = cache,
      config = config
    )
  except Exception as e:
    result.error = e
    result.ok = false
  finally:
    closeParser(pars)
  if result.ok == false:
    return result

  try:
    discard parseAll(pars)
  except ParseError as e:
    result.ok = false
    result.error = e
  finally:
    closeParser(pars)

when isMainModule:

  let r = parsePNodeStr("	const a = 1",currentSourcePath)
  echo r.ok
  echo r.error.name
  echo r.error.msg

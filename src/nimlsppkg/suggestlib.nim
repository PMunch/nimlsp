#when not defined(nimcore):
#  {.error: "nimcore MUST be defined for Nim's core tooling".}

import strutils, os, parseopt, parseutils, sequtils, net, rdstdin#, sexp
# Do NOT import suggest. It will lead to wierd bugs with
# suggestionResultHook, because suggest.nim is included by sigmatch.
# So we import that one instead.
import compiler / [options, commands, modules, sem,
  passes, passaux, msgs, nimconf,
  extccomp, condsyms,
  sigmatch, ast, scriptconfig,
  idents, modulegraphs, vm, prefixmatches, lineinfos, cmdlinehelper,
  pathutils]

import messageenums
export Suggest

when defined(windows):
  import winlean
else:
  import posix

type NimSuggest* = distinct ModuleGraph

proc myLog(s: string) =
  echo s

proc findNode(n: PNode; trackPos: TLineInfo): PSym =
  #echo "checking node ", n.info
  if n.kind == nkSym:
    if isTracked(n.info, trackPos, n.sym.name.s.len): return n.sym
  else:
    for i in 0 ..< safeLen(n):
      let res = findNode(n[i], trackPos)
      if res != nil: return res

proc symFromInfo(graph: ModuleGraph; trackPos: TLineInfo): PSym =
  let m = graph.getModule(trackPos.fileIndex)
  if m != nil and m.ast != nil:
    result = findNode(m.ast, trackPos)

proc execute*(nimsuggest: NimSuggest, cmd: IdeCmd, file, dirtyfile: AbsoluteFile, line, col: int): seq[Suggest] =
  let
    graph = nimsuggest.ModuleGraph
    conf = graph.config
  conf.ideCmd = cmd
  conf.compileOptions = " -w"
  writeFile("/tmp/suglibconf", graph.repr)
  if conf.ideCmd == ideKnown:
    return @[Suggest(section: ideKnown, quality: ord(fileInfoKnown(conf, file)))]
  else:
    var retval: seq[Suggest]
    proc sugResultHook(s: Suggest) =
      retval.add(s)
    proc errorHook(conf: ConfigRef; info: TLineInfo; msg: string; sev: Severity) =
      retval.add(Suggest(section: ideChk, filePath: toFullPath(conf, info),
        line: toLinenumber(info), column: toColumn(info), doc: msg,
        forth: $sev))
    conf.suggestionResultHook = sugResultHook
    myLog("cmd: " & $cmd & ", file: " & file.string &
          ", dirtyFile: " & dirtyfile.string &
          "[" & $line & ":" & $col & "]")
    if cmd == ideChk:
      conf.structuredErrorHook = errorHook
      conf.writelnHook = myLog
    else:
      conf.structuredErrorHook = nil
      conf.writelnHook = myLog
    if cmd == ideUse and conf.suggestVersion != 0:
      graph.resetAllModules()
    var isKnownFile = true
    let dirtyIdx = fileInfoIdx(conf, file, isKnownFile)

    if not dirtyfile.isEmpty: msgs.setDirtyFile(conf, dirtyIdx, dirtyfile)
    else: msgs.setDirtyFile(conf, dirtyIdx, AbsoluteFile"")

    conf.m.trackPos = newLineInfo(dirtyIdx, line, col)
    conf.m.trackPosAttached = false
    conf.errorCounter = 0
    if conf.suggestVersion == 1:
      graph.usageSym = nil
    if not isKnownFile:
      graph.compileProject()
    if conf.suggestVersion == 0 and conf.ideCmd in {ideUse, ideDus} and
        dirtyfile.isEmpty:
      discard "no need to recompile anything"
    else:
      let modIdx = graph.parentModule(dirtyIdx)
      graph.markDirty dirtyIdx
      graph.markClientsDirty dirtyIdx
      if conf.ideCmd != ideMod:
        graph.compileProject(modIdx)
    if conf.ideCmd in {ideUse, ideDus}:
      let u = if conf.suggestVersion != 1: graph.symFromInfo(conf.m.trackPos) else: graph.usageSym
      if u != nil:
        listUsages(conf, u)
      else:
        localError(conf, conf.m.trackPos, "found no symbol at this position " & (conf $ conf.m.trackPos))
    return retval


proc startNimSuggest*(path: string): NimSuggest =
  let
    cache = newIdentCache()
    conf = newConfigRef()
    binaryPath = findExe("nim")
  if binaryPath == "":
    raise newException(IOError,
        "Cannot find Nim standard library: Nim compiler not in PATH")

  # From initDefinesProg
  condsyms.initDefines(conf.symbols)
  defineSymbol conf.symbols, "nimsuggest"

  # From processCmdLine
  let a = unixToNativePath(path)
  if dirExists(a) and not fileExists(a.addFileExt("nim")):
    conf.projectName = findProjectNimFile(conf, a)
    # don't make it worse, report the error the old way:
    if conf.projectName.len == 0: conf.projectName = a
  else:
    conf.projectName = a
  # if processArgument(pass, p, argsCount): break

  # From processCmdLineAndProjectPath
  try:
    conf.projectFull = canonicalizePath(conf, AbsoluteFile conf.projectName)
  except OSError:
    conf.projectFull = AbsoluteFile conf.projectName
  let p = splitFile(conf.projectFull)
  let dir = if p.dir.isEmpty: AbsoluteDir getCurrentDir() else: p.dir
  conf.projectPath = AbsoluteDir canonicalizePath(conf, AbsoluteFile dir)
  conf.projectName = p.name

  conf.projectName = conf.projectFull.string

  # From handleCmdLine
  conf.prefixDir = AbsoluteDir binaryPath.splitPath().head.parentDir()
  if not dirExists(conf.prefixDir / RelativeDir"lib"):
    conf.prefixDir = AbsoluteDir""

  # From loadConfigsAndRunMainProgram
  loadConfigs(DefaultConfig, cache, conf) # load all config files
  conf.command = "nimsuggest"
  proc runNimScriptIfExists(path: AbsoluteFile)=
    if fileExists(path):
      runNimScript(cache, path, freshDefines = false, conf)

  # Caution: make sure this stays in sync with `loadConfigs`
  if optSkipSystemConfigFile notin conf.globalOptions:
    runNimScriptIfExists(getSystemConfigPath(conf, DefaultConfigNims))

  if optSkipUserConfigFile notin conf.globalOptions:
    runNimScriptIfExists(getUserConfigPath(DefaultConfigNims))

  if optSkipParentConfigFiles notin conf.globalOptions:
    for dir in parentDirs(conf.projectPath.string, fromRoot = true, inclusive = false):
      runNimScriptIfExists(AbsoluteDir(dir) / DefaultConfigNims)

  if optSkipProjConfigFile notin conf.globalOptions:
    runNimScriptIfExists(conf.projectPath / DefaultConfigNims)
  block:
    let scriptFile = conf.projectFull.changeFileExt("nims")
    if scriptFile != conf.projectFull:
      runNimScriptIfExists(scriptFile)
    else:
      # 'nimsuggest foo.nims' means to just auto-complete the NimScript file
      discard

  let graph = newModuleGraph(cache, conf)
  graph.suggestMode = true

  # From main command
  clearPasses(graph)
  registerPass graph, verbosePass
  registerPass graph, semPass
  graph.config.cmd = cmdIdeTools
  wantMainModule(graph.config)

  if not fileExists(graph.config.projectFull):
    quit "cannot find file: " & graph.config.projectFull.string

  add(graph.config.searchPaths, graph.config.libpath)

  # do not stop after the first error:
  graph.config.errorMax = high(int)
  # do not print errors, but log them
  #graph.config.writelnHook = myLog
  graph.config.structuredErrorHook = nil

  # compile the project before showing any input so that we already
  # can answer questions right away:
  compileProject(graph)
  return graph.NimSuggest

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
    nimsuggest.execute(`ide command`, AbsoluteFile file, AbsoluteFile dirtyfile, line, col)

template createFileOnlyCommand(command: untyped) {.dirty.} =
  proc command*(nimsuggest: NimSuggest, file: string, dirtyfile = ""): seq[Suggest] =
    nimsuggest.execute(`ide command`, AbsoluteFile file, AbsoluteFile dirtyfile, 0, 0)

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
  var graph = initNimSuggest("/home/peter/Projects/nimlsp/lib/nimsuggest/suglibtest.nim")
  var suggestions = execute(graph, ideSug, AbsoluteFile "/home/peter/Projects/nimlsp/lib/nimsuggest/suglibtest.nim", AbsoluteFile "/home/peter/Projects/nimlsp/lib/nimsuggest/suglibtest.nim", 7, 2)
  for suggestion in suggestions:
    echo suggestion

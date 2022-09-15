import std/os

const explicitSourcePath {.strdefine.} = getCurrentCompilerExe().parentDir.parentDir
switch "path", explicitSourcePath

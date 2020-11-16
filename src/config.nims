import os

switch "path", getCurrentCompilerExe().parentDir.parentDir
--gc:markAndSweep

switch "hint","XDeclaredButNotUsed:off"

--path:"$lib/packages/docutils"

--define:useStdoutAsStdmsg
--define:nimsuggest
--define:nimcore

# die when nimsuggest uses more than 4GB:
when defined(cpu32):
  switch "define","nimMaxHeap=2000"
else:
  switch "define","nimMaxHeap=4000"

--threads:on
switch "warning","[Spacing]:off" # The JSON schema macro uses a syntax similar to TypeScript
switch "warning","[CaseTransition]:off"
switch "define","nimOldCaseObjects"
switch "backend","c"

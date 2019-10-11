import strformat, os

const path = fmt"{currentSourcePath}".parentDir.parentDir.parentDir

writeFile("src/nimlsp.nim.cfg","""
gc:markAndSweep

hint[XDeclaredButNotUsed]:off

path:"$lib/packages/docutils"
path:"""" & path & """"

define:useStdoutAsStdmsg
define:nimsuggest
define:nimcore
define:release

# die when nimsuggest uses more than 4GB:
@if cpu32:
  define:"nimMaxHeap=2000"
@else:
  define:"nimMaxHeap=4000"
@end

--threads:on
--warning[Spacing]:off # The JSON schema macro uses a syntax similar to TypeScript
--warning[CaseTransition]:off
-d:nimOldCaseObjects
""")

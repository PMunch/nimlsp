from std/os import osLastError, raiseOSError
from std/posix import SIGHUP, getpid, getppid, kill

when defined(linux):
  # `prctl` C FFI bindings
  proc prctl(option: cint): cint {.importc, header: "<sys/prctl.h>", varargs.}
  let prSetPdeathsig {.importc: "PR_SET_PDEATHSIG", header: "<sys/prctl.h>".}: cint

# Make nimlsp die when its parent process dies.
# Fixes https://github.com/PMunch/nimlsp/issues/180 (at least for GNU/Linux).
template dieWithParent*(signal: cint = SIGHUP): void =
  when defined(linux):
    block:
      let originalParent = getppid()
      if prctl(prSetPdeathsig, signal.culong, 0.culong, 0.culong, 0.culong) != 0:
        raiseOSError(osLastError())
      # The parent may have died between getppid() and prctl().
      if getppid() != originalParent: discard kill(getpid(), signal)
  else:
    discard # No-op if not GNU/Linux

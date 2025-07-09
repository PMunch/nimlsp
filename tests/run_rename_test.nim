import std/[os, osproc]

# Compile and run the rename test
let testFile = currentSourcePath().parentDir / "trename.nim"
let nimlspExe = parentDir(parentDir(currentSourcePath())) / "nimlsp"

echo "Building nimlsp..."
let buildResult = execCmd("nim c -r " & nimlspExe & ".nim")
if buildResult != 0:
  echo "Failed to build nimlsp"
  quit(1)

echo "Running rename test..."
let testResult = execCmd("nim c -r " & testFile)
if testResult != 0:
  echo "Rename test failed"
  quit(1)
else:
  echo "Rename test passed successfully!" 
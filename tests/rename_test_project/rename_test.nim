# Test file for rename functionality
var testVariable* = 42
let testConstant* = "hello"

proc testFunction*(x: int): int =
  result = x + testVariable

proc anotherFunction(y: string): string =
  result = y & testConstant

# Usage of the variables and functions
echo testFunction(10)
echo anotherFunction("world")
echo testVariable
echo testConstant 
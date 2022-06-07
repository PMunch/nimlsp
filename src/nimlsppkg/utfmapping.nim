import std/unicode


type FingerTable = seq[tuple[u16pos, offset: int]]

proc createUTFMapping*(line: string): FingerTable =
  var pos = 0
  for rune in line.runes:
    #echo pos
    #echo rune.int32
    case rune.int32:
      of 0x0000..0x007F:
        # One UTF-16 unit, one UTF-8 unit
        pos += 1
      of 0x0080..0x07FF:
        # One UTF-16 unit, two UTF-8 units
        result.add (u16pos: pos, offset: 1)
        pos += 1
      of 0x0800..0xFFFF:
        # One UTF-16 unit, three UTF-8 units
        result.add (u16pos: pos, offset: 2)
        pos += 1
      of 0x10000..0x10FFFF:
        # Two UTF-16 units, four UTF-8 units
        result.add (u16pos: pos, offset: 2)
        pos += 2
      else: discard

  #echo fingerTable

proc utf16to8*(fingerTable: FingerTable, utf16pos: int): int =
  result = utf16pos
  for finger in fingerTable:
    if finger.u16pos < utf16pos:
      result += finger.offset
    else:
      break

when isMainModule:
  import termstyle
  var x = "heållo☀☀wor𐐀𐐀☀ld heållo☀wor𐐀ld heållo☀wor𐐀ld"
  var fingerTable = populateUTFMapping(x)

  var corrected = utf16to8(fingerTable, 5)
  for y in x:
    if corrected == 0:
      echo "-"
    if ord(y) > 125:
      echo ord(y).red
    else:
      echo ord(y)
    corrected -= 1

  echo "utf16\tchar\tutf8\tchar\tchk"
  var pos = 0
  for c in x.runes:
    stdout.write pos
    stdout.write '\t'
    stdout.write c
    stdout.write '\t'
    var corrected = utf16to8(fingerTable, pos)
    stdout.write corrected
    stdout.write '\t'
    stdout.write x.runeAt(corrected)
    if c.int32 == x.runeAt(corrected).int32:
      stdout.write "\tOK".green
    else:
      stdout.write "\tERR".red
    stdout.write '\n'
    if c.int >= 0x10000:
      pos += 2
    else:
      pos += 1

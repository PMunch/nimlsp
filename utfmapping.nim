import unicode
import termstyle

var fingerTable: seq[tuple[u16pos, offset: int]]

var x = "heåll𐐀o"

var pos = 0
for rune in x.runes:
  echo pos
  echo rune.int32
  case rune.int32:
    of 0x0000..0x007F:
      pos += 1
    of 0x0080..0x07FF:
      fingerTable.add (u16pos: pos, offset: 1)
      pos += 1
    of 0x0800..0xFFFF:
      fingerTable.add (u16pos: pos, offset: 1)
      pos += 2
    of 0x10000..0x10FFFF:
      fingerTable.add (u16pos: pos, offset: 2)
      pos += 2
    else: discard

echo fingerTable

let utf16pos = 5
var corrected = utf16pos
for finger in fingerTable:
  if finger.u16pos < utf16pos:
    corrected += finger.offset
  else:
    break

for y in x:
  if corrected == 0:
    echo "-"
  if ord(y) > 125:
    echo ord(y).red
  else:
    echo ord(y)
  corrected -= 1

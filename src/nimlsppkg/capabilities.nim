## Helper functions to check what the client supports

import std/json

using caps: ClientCapabilities

func supportsHierarchicalSymbols*(caps): bool =
  ## True if the client supports having heirarchal
  ## symbols in the document outline
  JsonNode(caps){"textDocument", "documentSymbol", "hierarchicalDocumentSymbolSupport"} == %true

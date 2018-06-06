==========
Nim Language Server Protocol
==========

This is the beginning of what might become a `Language Server Protocol
<https://microsoft.github.io/language-server-protocol/>`_ implementation in
Nim, for Nim. The idea is to wrap nimsuggest and possibly other tools in order
to supply the actual information while keeping this entirely an interface
layer. Currently this is only a few simple procedures parsing and creating some

JSON objects that correspond with the specification.
=======

JSON objects that correspond with the specification. This is intended to be a
team effort, so help out in any way you can. If you need pointers look at the
issues board for something that needs doing, or create your own issues if you
feel something needs to be done or discussed.

Supported Protocol features
=======

- [TODO] textDocument/didChange
- [TODO] textDocument/didClose
- [TODO] textDocument/didOpen
- [TODO] textDocument/didSave

- [TODO] textDocument/codeAction
- [TODO] textDocument/completion
- [TODO] textDocument/definition
- [TODO] textDocument/documentHighlight
- [TODO] textDocument/documentSymbol
- [TODO] textDocument/executeCommand
- [TODO] textDocument/format
- [TODO] textDocument/hover
- [TODO] textDocument/rename
- [TODO] textDocument/references
- [TODO] textDocument/signatureHelp
- [TODO] workspace/symbol

Run Tests
=========

.. code:: bash

    nimble test

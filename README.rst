==========
Nim Language Server Protocol
==========

This is the beginning of what might become a `Language Server Protocol
<https://microsoft.github.io/language-server-protocol/>`_ implementation in
Nim, for Nim. The idea is to wrap nimsuggest and possibly other tools in order
to supply the actual information while keeping this entirely an interface
layer. This is intended to be a team effort, so help out in any way you can.
If you need pointers look at the issues board for something that needs doing,
or create your own issues if you feel something needs to be done or discussed.

Compile `nimlsp`
=======
.. code:: bash

    nimble build

or if you want debug output

.. code:: bash

    nimble debug

Supported Protocol features
=======

- [x] textDocument/didChange
- [x] textDocument/didClose
- [x] textDocument/didOpen
- [ ] textDocument/didSave

- [ ] textDocument/codeAction
- [x] textDocument/completion
- [x] textDocument/definition
- [ ] textDocument/documentHighlight
- [ ] textDocument/documentSymbol
- [ ] textDocument/executeCommand
- [ ] textDocument/format
- [x] textDocument/hover
- [ ] textDocument/rename
- [x] textDocument/references
- [ ] textDocument/signatureHelp
- [ ] workspace/symbol

Run Tests
=========

.. code:: bash

    nimble test

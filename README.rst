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

Setting up `nimlsp`
=======
So far the only editor `nimlsp` has been tried in is Sublime. If you want to
try it out (or want some ideas on how to set it up for another editor) this is
how it's done in Sublime:

First you need a LSP client, the one that's been tested is
https://github.com/tomv564/LSP. It's certainly not perfect, but it works well
enough.

Once you have it installed you'll want to grab NimLime as well. NimLime can
perform many of the same features that `nimlsp` does, but we're only interested
in syntax highlighting and some definitions. If you know how to disable the
overlapping features or achieve this in another way please update this section.

Now in order to set up LSP itself enter it's settings and add this:
.. code:: json

   {
      "clients":
      {
         "nim":
         {
            "command":
            [
               "<path to nimlsp>/nimlsp" // This can be changed if you put nimlsp in your PATH
            ],
            "enabled": true,
            "env":
            {
               "PATH": "<home directory>/.nimble/bin" // To be able to find nimsuggest, can be changed if you have nimsuggest in your PATH
            },
            "languageId": "nim",
            "scopes":
            [
               "source.nim"
            ],
            "syntaxes":
            [
               "Packages/NimLime/Syntaxes/Nim.tmLanguage"
            ]
         }
      },
      // These are mostly for debugging feel free to remove them
      // If you build nimlsp without debug information it doesn't
      // write anything to stderr
      "log_payloads": true,
      "log_stderr": true
   }

Run Tests
=========

.. code:: bash

    nimble test

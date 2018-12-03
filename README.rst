==========
Nim Language Server Protocol
==========

This is a `Language Server Protocol
<https://microsoft.github.io/language-server-protocol/>`_ implementation in
Nim, for Nim. It is based on nimsuggest, which means that every editor that
supports LSP will now have the same quality of suggestions that has previously
only been available in supported editors.

Installing `nimlsp`
=======
# TODO: Invest if this works with the git submodule
The easiest way to install `nimlsp` is to use `nimble` with:
.. code:: bash

    nimble install nimlsp

This will compile and install it in the `nimble` binary directory, which if
you've set it up correctly should be in your path. When using `nimlsp` it needs
to have Nims sources available.

Compile `nimlsp`
=======
.. code:: bash

    nimble build

or if you want debug output

.. code:: bash

    nimble debug

Supported Protocol features
=======

======  ================================
Status  LSP Command
======  ================================
☑ DONE  textDocument/didChange
☑ DONE  textDocument/didClose
☑ DONE  textDocument/didOpen
☑ DONE  textDocument/didSave
☐ TODO  textDocument/codeAction
☑ DONE  textDocument/completion
☑ DONE  textDocument/definition
☐ TODO  textDocument/documentHighlight
☐ TODO  textDocument/documentSymbol
☐ TODO  textDocument/executeCommand
☐ TODO  textDocument/format
☑ DONE  textDocument/hover
☑ DONE  textDocument/rename
☑ DONE  textDocument/references
☐ TODO  textDocument/signatureHelp
☑ DONE  textDocument/publishDiagnostics
☐ TODO  workspace/symbol
======  ================================


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

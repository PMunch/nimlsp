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
The easiest way to install `nimlsp` is to use `nimble` with:

.. code:: bash

   nimble install nimlsp

This will compile and install it in the `nimble` binary directory, which if
you've set it up correctly should be in your path. When using `nimlsp` it needs
to have Nims sources available to know the types in the standard library. This
defaults to something that should work with the regular installation, but you
can set it on compile-time with `-d:explicitSourcePath=PATH`, or on runtime by
supplying it as an argument to `nimlsp`. How exectly to do that will depend on
the LSP client.

Compile `nimlsp`
=======
If you want more control over the compilation feel free to clone the
repository. `nimlsp` depends on the `nimsuggest` sources which is in the main
Nim repository. This means you can either clone the Nim repository with

.. code:: bash

   git submodule update --recursive --remote

Or if you don't want a full clone of the Nim sources you can copy just the
nimsuggest folder into the `Nim` folder in `src/nimlsppkg`. This means the
default source path will not work as well so either set it explicitly on
compilation with `-d:explicitSourcePath=PATH` or on runtime.

To do the standard build run:

.. code:: bash

   nimble build

Or if you want debug output when `nimlsp` is running:

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
Sublime
-------
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

Vim
-------
To use `nimlsp` in Vim install the `prabirshrestha/vim-lsp` plugin and
dependencies:

.. code:: vim

   Plugin 'prabirshrestha/asyncomplete.vim'
   Plugin 'prabirshrestha/async.vim'
   Plugin 'prabirshrestha/vim-lsp'
   Plugin 'prabirshrestha/asyncomplete-lsp.vim'

Then set it up to use `nimlsp` for Nim files:

.. code:: vim

   if executable('nimlsp')
      au User lsp_setup call lsp#register_server({
        \ 'name': 'nimlsp',
        \ 'cmd': {server_info->['nimlsp']},
        \ 'whitelist': ['nim'],
        \ })
   endif

   let g:lsp_log_verbose = 1
   let g:lsp_log_file = expand('/tmp/vim-lsp.log')

   " for asyncomplete.vim log
   let g:asyncomplete_log_file = expand('/tmp/asyncomplete.log')

   let g:asyncomplete_auto_popup = 0

   function! s:check_back_space() abort
       let col = col('.') - 1
       return !col || getline('.')[col - 1]  =~ '\s'
   endfunction

   inoremap <silent><expr> <TAB>
     \ pumvisible() ? "\<C-n>" :
     \ <SID>check_back_space() ? "\<TAB>" :
     \ asyncomplete#force_refresh()
   inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

This configuration allows you to hit Tab to get auto-complete, and to call
various functions to rename and get definitions. Of course you are free to
configure this any way you'd like.

Run Tests
=========
Not too many at the moment unfortunately, but they can be run with:

.. code:: bash

    nimble test

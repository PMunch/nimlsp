==========
Nim Language Server Protocol
==========

This is a `Language Server Protocol
<https://microsoft.github.io/language-server-protocol/>`_ implementation in
Nim, for Nim.
It is based on nimsuggest, which means that every editor that
supports LSP will now have the same quality of suggestions that has previously
only been available in supported editors.

Installing ``nimlsp``
=======
If you have installed Nim through ``choosenim`` (recommended) the easiest way to
install ``nimlsp`` is to use ``nimble`` with:

.. code:: bash

   nimble install nimlsp

This will compile and install it in the ``nimble`` binary directory, which if
you have set up ``nimble`` correctly it should be in your path. When compiling
and using ``nimlsp`` it needs to have Nim's sources available in order to work.
With Nim installed through ``choosenim`` these should already be on your system
and ``nimlsp`` should be able to find and use them automatically. However if you
have installed ``nimlsp`` in a different way you might run into issues where it
can't find certain files during compilation/running. To fix this you need to
grab a copy of Nim sources and then point ``nimlsp`` at them on compile-time by
using ``-d:explicitSourcePath=PATH``, where ``PATH`` is where you have your Nim
sources. You can also pass them at run-time (if for example you're working with
a custom copy of the stdlib by passing it as an argument to ``nimlsp``. How
exectly to do that will depend on the LSP client.

Compile ``nimlsp``
=======
If you want more control over the compilation feel free to clone the
repository. ``nimlsp`` depends on the ``nimsuggest`` sources which are in the main
Nim repository, so make sure you have a copy of that somewhere. Manually having a
copy of Nim this way means the default source path will not work so you need to
set it explicitly on compilation with ``-d:explicitSourcePath=PATH`` and point to
it at runtime (technically the runtime should only need the stdlib, so omitting
it will make ``nimlsp`` try to find it from your Nim install).

To do the standard build run:

.. code:: bash

   nimble build

Or if you want debug output when ``nimlsp`` is running:

.. code:: bash

   nimble debug

Or if you want even more debug output from the LSP format:

.. code:: bash

   nimble debug -d:debugLogging

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
☑ DONE  textDocument/documentSymbol
☐ TODO  textDocument/executeCommand
☐ TODO  textDocument/format
☑ DONE  textDocument/hover
☑ DONE  textDocument/rename
☑ DONE  textDocument/references
☑ DONE  textDocument/signatureHelp
☑ DONE  textDocument/publishDiagnostics
☐ TODO  workspace/symbol
======  ================================


Setting up ``nimlsp``
=======
Sublime Text
-------
Install the `LSP plugin <https://packagecontrol.io/packages/LSP>`_.
Install the `NimLime plugin <https://packagecontrol.io/packages/NimLime>`_ for syntax highlighting.

Apart from syntax highlighting, NimLime can perform many of the features that ``nimlsp`` provides.
It is recommended to disable those for optimal experience.
For this, navigate to ``Preferences > Package Settings > NimLime > Settings`` and set ``*.enabled`` settings to ``false``:

.. code:: js

   {
      "error_handler.enabled": false,
      "check.on_save.enabled": false,
      "check.current_file.enabled": false,
      "check.external_file.enabled": false,
      "check.clear_errors.enabled": false,
   }

To set up LSP, run ``Preferences: LSP settings`` from the command palette and add the following:

.. code:: js

   {
      "clients": {
         "nimlsp": {
            "command": ["nimlsp"],
            "enabled": true,

            // ST4 only
            "selector": "source.nim",

            // ST3 only
            "languageId": "nim",
            "scopes": ["source.nim"],
            "syntaxes": ["Packages/NimLime/Syntaxes/Nim.tmLanguage"]
         }
      }
   }

*Note: Make sure ``<path/to>/.nimble/bin`` is added to your ``PATH``.*

Vim
-------
To use ``nimlsp`` in Vim install the ``prabirshrestha/vim-lsp`` plugin and
dependencies:

.. code:: vim

   Plugin 'prabirshrestha/asyncomplete.vim'
   Plugin 'prabirshrestha/async.vim'
   Plugin 'prabirshrestha/vim-lsp'
   Plugin 'prabirshrestha/asyncomplete-lsp.vim'

Then set it up to use ``nimlsp`` for Nim files:

.. code:: vim

   let s:nimlspexecutable = "nimlsp"
   let g:lsp_log_verbose = 1
   let g:lsp_log_file = expand('/tmp/vim-lsp.log')
   " for asyncomplete.vim log
   let g:asyncomplete_log_file = expand('/tmp/asyncomplete.log')

   let g:asyncomplete_auto_popup = 0

   if has('win32')
      let s:nimlspexecutable = "nimlsp.cmd"
      " Windows has no /tmp directory, but has $TEMP environment variable
      let g:lsp_log_file = expand('$TEMP/vim-lsp.log')
      let g:asyncomplete_log_file = expand('$TEMP/asyncomplete.log')
   endif
   if executable(s:nimlspexecutable)
      au User lsp_setup call lsp#register_server({
      \ 'name': 'nimlsp',
      \ 'cmd': {server_info->[s:nimlspexecutable]},
      \ 'whitelist': ['nim'],
      \ })
   endif

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

Emacs
-------

With lsp-mode and use-package:

.. code:: emacs-lisp

   (use-package nim-mode
     :ensure t
     :hook
     (nim-mode . lsp))

Intellij
-------
You will need to install the `LSP support plugin <https://plugins.jetbrains.com/plugin/10209-lsp-support>`_.
For syntax highlighting i would recommend the "official" `nim plugin <https://plugins.jetbrains.com/plugin/15128-nim>`_
(its not exactly official, but its developed by an intellij dev), the plugin will eventually use nimsuggest and have support for 
all this things and probably more, but since its still very new most of the features are still not implemented, so the LSP is a
decent solution (and the only one really).

To use it:

1. Install the LSP and the nim plugin.

2. Go into ``settings > Language & Frameworks > Language Server Protocol > Server Definitions``.

3. Set the LSP mode to ``executable``, the extension to ``nim`` and in the Path, the path to your nimlsp executable.

4. Hit apply and everything should be working now.

Kate
-------
The LSP plugin has to be enabled in the Kate (version >= 19.12.0) plugins menu:

1. In ``Settings > Configure Kate > Application > Plugins``, check box next to ``LSP Client`` to enable LSP functionality.

2. Go to the now-available LSP Client menu (``Settings > Configure Kate > Application``) and enter the following in the User Server Settings tab:

.. code:: json

   {
       "servers": {
           "nim": {
               "command": [".nimble/bin/nimlsp"],
               "url": "https://github.com/PMunch/nimlsp",
               "highlightingModeRegex": "^Nim$"
           }
       }
   }

This assumes that nimlsp was installed through nimble.
*Note: Server initialization may fail without full path specified, from home directory, under the ``"command"`` entry, even if nimlsp is in system's ``PATH``.*

Run Tests
=========
Not too many at the moment unfortunately, but they can be run with:

.. code:: bash

    nimble test

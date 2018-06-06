==========
Nim Language Server Protocol
==========

This is the beginning of what might become a `Language Server Protocol
<https://microsoft.github.io/language-server-protocol/>`_ implementation in
Nim, for Nim. The idea is to wrap nimsuggest and possibly other tools in order
to supply the actual information while keeping this entirely an interface
layer. Currently this is only a few simple procedures parsing and creating some
JSON objects that correspond with the specification.


Run Tests
=========

.. code:: bash

    nimble test

[![Build](https://travis-ci.org/serprex/luwa.svg?branch=master)](https://travis-ci.org/serprex/luwa)

Luwa's end goal is to JIT to [WASM](https://webassembly.org). Right now it's a bit of a learning environment for me as I've never [written a language implementation](https://esolangs.org/wiki/User:Serprex) that required real parsing

I'll try avoid my usual stream of consciousness here, instead that's at [my devlog](https://patreon.com/serprex)

`main.js` is the nodejs entrypoint

WASM runtime is in `rt/`. `rt/make.lua` is the entry point for the assmembler. This produces an `rt.wasm` which `rt.js` contains glue code for

The GC is a LISP2 compacting GC. GC performance is a low priority given the WASM GC RFC

The VM needs to be reentrant. Ideally this means having a constant WASM stack depths in the face of nested pcalls & coroutines. This means CALL\_FUNC can't use the `call` opcode unless it's a builtin. `pcall` will need to function through an exception handler frame on the in-memory callstack

Supporting lua code is in `luart/`. `prelude.lua` implements builtins which do not require hand written wasm

`scripts/luac.sh` is used to bootstrap `luart/` code

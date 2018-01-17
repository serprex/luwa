[![Build](https://travis-ci.org/serprex/luwa.svg?branch=master)](https://travis-ci.org/serprex/luwa)

Luwa's end goal is to JIT to [WASM](https://webassembly.org). Right now it's a bit of a learning environment for me as I've never [written a language implementation](https://esolangs.org/wiki/User:Serprex) that required real parsing

I'll try avoid my usual stream of consciousness here, instead that's at [my devlog](https://patreon.com/serprex)

[`main.js`](main.js) is the nodejs entrypoint

WASM runtime is in `rt/`. [`rt/make.lua`](rt/make.lua) is the entry point for the assmembler. This produces an `rt.wasm` which [`rt.js`](rt.js) contains glue code for

The GC is a LISP2 compacting GC. GC performance is a low priority given the WASM GC RFC. See [`rt/gc.lua`](rt/gc.lua)

The VM needs to be reentrant. The currently running coroutine is oluastack. Builtins which call functions work by returning after setting up a necessary callstack. See [`rt/vm.lua`](rt/vm.lua)

[`rt/prelude.lua`](rt/prelude.lua) implements builtins which do not require hand written wasm

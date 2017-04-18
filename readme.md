[![Build](https://travis-ci.org/serprex/luwa.svg?branch=master)](https://travis-ci.org/serprex/luwa)

Luwa's end goal is to JIT to [WASM](https://webassembly.org). Right now it's a bit of a learning environment for me as I've never [written a language implementation](https://esolangs.org/wiki/User:Serprex) that required real parsing

I'll try avoid my usual stream of consciousness here, instead that's at [my devlog](https://patreon.com/serprex)

`luwa.js` shows the pipeline: `lex.js` -> `ast.js` -> `bc.js` -> `runbc.js`

`lex.js` is a linear scan, so I'll leave that as an exercise for the reader

`ast.js` is some adhoc parser combinator thing with generators. Combinators return the rightmost AST node. The rest of their function is left as an exercise to the reader
AST is immutable during the parse phase so that backtracking has no cleanup
Some post processing is done to convert from children pointing at parents to parents pointing at children

`bc.js` runs two passes over the AST: scoping & codegen. I should probably split it into 2 files

`runbc.js` interprets the output of `bc.js`

### Other js files
File | Description
--- | ---
\_test.js | unit tests
env.js | exports a function which returns the default `_ENV`
func.js | ast.js's Assembler can be boiled down to func.js's Func, which is what runbc uses in conjuction with a stack to interpret
main.js | this should be fixed up to be a node frontend
obj.js | where metatable logic will go. Metatables are maintained as a [WeakMap](https://developer.mozilla.org/en/docs/Web/JavaScript/Reference/Global_Objects/WeakMap) of objects to metatables
string.js | string library
table.js | table type
thread.js | thread type returned by `coroutine.create`
ui.js | index.html's js logic
uf8.js | this'll matter more once strings are Uint8Arrays

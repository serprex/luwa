#!/bin/sh
# Builds the reference Lua to bench/lua.wasm with wasi-sdk, for scripts/bench.js.
#   WASI_SDK: wasi-sdk dir, default wasi-sdk/ in the repo.
#     Unpack a release from https://github.com/WebAssembly/wasi-sdk/releases there (25 works)
#   LUA_SRC: Lua source dir, needs onelua.c. Default lua-5.5.1/ in the repo
# Lua's errors use setjmp/longjmp, which wasi-sdk builds with wasm exceptions.
# wasi has no system, tmpnam or tmpfile, so those always fail
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
WASI_SDK=${WASI_SDK:-$root/wasi-sdk}
LUA_SRC=${LUA_SRC:-$root/lua-5.5.1}
out=$root/bench/lua.wasm
stub=$(mktemp --suffix=.c)
printf '#include <stdio.h>\nFILE *tmpfile(void) { return NULL; }\n' > "$stub"
"$WASI_SDK/bin/clang" --sysroot="$WASI_SDK/share/wasi-sysroot" --target=wasm32-wasip1 -O2 \
	'-Dl_system(c)=((c)==0?0:-1)' -DLUA_TMPNAMBUFSIZE=32 '-Dlua_tmpnam(b,e)=(e=1)' \
	-D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -mllvm -wasm-enable-sjlj \
	-w -o "$out" "$LUA_SRC/onelua.c" "$stub" \
	-lwasi-emulated-signal -lwasi-emulated-process-clocks -lsetjmp -lm
rm "$stub"
echo "wrote bench/lua.wasm"

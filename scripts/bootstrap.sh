#!/bin/sh
# Self-bootstrap check. stage1 is rt.wasm built by host Lua,
# stage2 is built by luwa running on stage1, stage3 by luwa running on stage2.
# stage2 == stage3 is the test. stage1 == stage2 too, while host Lua & luwa agree.
# Also checks luwa makes the same comp.wasm as host Lua.
# Leaves rt.wasm as stage1
set -e
dir=$(mktemp -d)
lua rt/mkrt.lua "$dir/stage1.wasm"
cp "$dir/stage1.wasm" rt.wasm
node main.js rt/mkrt.lua "$dir/stage2.wasm"
cp "$dir/stage2.wasm" rt.wasm
node main.js rt/mkrt.lua "$dir/stage3.wasm"
cp "$dir/stage1.wasm" rt.wasm
cmp "$dir/stage2.wasm" "$dir/stage3.wasm"
echo 'stage2 == stage3'
cmp "$dir/stage1.wasm" "$dir/stage2.wasm" && echo 'stage1 == stage2'

lua rt/mkcomp.lua
cp scripts/comp.wasm "$dir/comp.host.wasm"
node main.js rt/mkcomp.lua
cmp scripts/comp.wasm "$dir/comp.host.wasm" && echo 'comp.wasm same'
rm -r "$dir"

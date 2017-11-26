#!/bin/sh
OUT="$1"
shift
echo 'return function() return ' > "$OUT"
for f in "$@"
do ./scripts/luac-lex.js "$f" | ./scripts/luac-bcgen.lua >> "$OUT"
done
echo 'end' > "$OUT"

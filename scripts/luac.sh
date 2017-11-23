#!/bin/sh
./scripts/luac-lex.js "$1" | ./scripts/luac-bcgen.lua #> "$1".bc

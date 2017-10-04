#!/bin/sh
./luac-lex.js "$1" | ./luac-bcgen.lua > "$1".bc

#!/usr/bin/env lua
-- Builds scripts/lex.wasm: just the lexer, for scripts/luac-lex.js at build time
-- (rt.wasm can't be built yet, it holds the prelude's bytecode)
package.path = 'rt/?.lua;' .. package.path
local M = require 'make'

local _lex = require '_lex'
local _js = require 'jsapi'

local lex = M.func(V, { V, V, V }, function(f, s)
	f:load(s)
	f:refcast(require('alloc').R.str)
	f:call(_lex.lex)
end)

local mod = M.mod()
mod:export('lex', lex)
for _, name in ipairs{ 'typeof', 'newstr', 'strlen', 'strget', 'strset', 'intval', 'fltval', 'veclen', 'vecget' } do
	mod:export(name, _js[name])
end
local chunks = mod:compile()

io.open('scripts/lex.wasm', 'w'):write(table.unpack(chunks)):close()

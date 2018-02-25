#!/usr/bin/env lua
package.path = 'rt/?.lua;' .. package.path
local M = require 'make'

local _stack = require 'stack'
local _table = require '_table'
local _rt = require 'rt'
local _vm = require 'vm'
local _alloc = require 'alloc'
local _gc = require 'gc'
local _lex = require '_lex'
local _env = require 'env'

local mod = M.mod()
local function export(obj, ...)
	print(obj, ...)
	for i=1, select('#', ...) do
		local name = select(i, ...)
		mod:export(name, obj[name])
	end
end
local function import(obj, ...)
	for i=1, select('#', ...) do
		mod:import(obj[select(i, ...)])
	end
end
export(_stack, 'tmppush', 'tmppop', 'tmpclear', 'nthtmp', 'setnthtmp')
export(_table, 'tblget', 'tblset')
export(_rt, 'getluastack', 'setluastack')
export(_vm, 'init', 'eval')
export(_alloc, 'newi64', 'newf64', 'newtbl', 'newstr', 'newvec', 'newvec1',
	'newstrbuf', 'newvecbuf', 'newfunc', 'newcoro')
export(_gc, 'gcmark')
export(_lex, 'lex')
export(_env, 'genesis', 'initPrelude')
import(_rt, 'memory', 'igcfix', 'igcmark', 'echo', 'echoptr', 'sin', 'cos', 'tan',
	'asin', 'acos', 'atan', 'atan2', 'exp', 'log')
mod:data(_rt.image)
local chunks = mod:compile()

io.open('rt.wasm', 'w'):write(table.unpack(chunks)):close()


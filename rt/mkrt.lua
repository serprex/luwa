#!/usr/bin/env lua
package.path = 'rt/?.lua;' .. package.path
local M = require 'make'

local _stack = require 'stack'
local _rt = require 'rt'
local _vm = require 'vm'
local _env = require 'env'
local _js = require 'jsapi'

local mod = M.mod()
local function export(obj, ...)
	for i=1, select('#', ...) do
		local name = select(i, ...)
		mod:export(name, assert(obj[name], name))
	end
end
local function import(obj, ...)
	for i=1, select('#', ...) do
		mod:import(obj[select(i, ...)])
	end
end
import(_rt, 'echoobj', 'sin', 'cos', 'tan',
	'asin', 'acos', 'atan', 'atan2', 'random', 'exp', 'log', 'pow', 'host', 'jitreq')
export(_stack, 'tmppush', 'tmppop', 'tmpclear', 'nthtmp', 'stacklen')
export(_vm, 'init', 'eval')
export(_env, 'genesis', 'initPrelude')
export(_js, 'typeof', 'newstr', 'newtbl', 'newi64', 'newf64', 'strlen', 'strget', 'strset',
	'intval', 'newbool', 'boolval', 'fltval', 'veclen', 'vecget', 'tblnext', 'tblmeta', 'tblget', 'tblset',
	'framelen', 'framefield', 'stackget', 'stacksize', 'fninfo', 'jitset')

-- The JIT module: every rt func & global its ops use is an import, which rt.wasm exports as j0, j1..
-- Small hot funcs are copied into it instead, so the engine can inline them.
-- jit.lua puts the JIT'd functions after this header
local inline = {}
for _, f in ipairs{ _stack.tmppush, _stack.tmppop, _stack.reserve, _stack.sget, _stack.sset, _stack.nthtmp,
		_stack.stacklen, _stack.ftop, _stack.fget, _stack.fset, require('alloc').boxi64, require('alloc').typeof } do
	inline[assert(f)] = true
end
local nextern = 0
local externs = {}
local function extern(obj)
	if inline[obj] then
		return nil
	end
	local imp = externs[obj]
	if not imp then
		local name = 'j' .. nextern
		nextern = nextern + 1
		if obj.isfunc then
			imp = M.importfunc('rt', name, table.unpack(obj.fty))
		else
			imp = M.importglobal('rt', name, obj.type, obj.mut)
		end
		externs[obj] = imp
		mod:export(name, obj)
	end
	return imp
end
-- A func's index counts the imports before it, so all imports have to come first.
-- The first pass finds them, the second builds with them in place
local jm = M.mod()
jm.extern = extern
_vm.jitpieces(jm)
local imports = jm._import
jm = M.mod()
jm.extern = extern
for _, imp in ipairs(imports) do
	jm:import(imp)
end
local jit = _vm.jitpieces(jm)
assert(#jm._import == #imports, 'jit: second pass found new imports')
jit.fty = jm:typeidx(require('alloc').jitfty)
jit.funcs = jm:funcbodies()
jit.nfuncs = jm.fid + #jit.funcs
jit.header = jm:header()
-- rt.wasm joins the pieces into a module at runtime, see jit.lua
local _jit = require 'jit'
mod:memory(_jit.mem)
mod:data(M.data(_jit.mem, 0, _jit.image(jit)))
mod:export('jitmem', _jit.mem)
export(_jit, 'jitbegin', 'jitbody', 'jitend')
-- names for the name section. std & co are otherwise only required while eval is built
for _, name in ipairs{ 'alloc', 'obj', 'util', 'stack', '_table', '_string', '_float', '_lex', 'rt', 'frame',
		'vm', 'env', 'jsapi', 'std', 'stdcoro', 'stddebug', 'stdmath', 'jit' } do
	M.namefuncs(name .. '.', require(name))
end
local chunks = mod:compile()

-- output file is rt.wasm, or the first arg
io.open(... or 'rt.wasm', 'w'):write(table.unpack(chunks)):close()

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
	'asin', 'acos', 'atan', 'atan2', 'random', 'exp', 'log', 'pow', 'host')
export(_stack, 'tmppush', 'tmppop', 'tmpclear', 'nthtmp', 'stacklen')
export(_vm, 'init', 'eval')
export(_env, 'genesis', 'initPrelude')
export(_js, 'typeof', 'newstr', 'newtbl', 'newi64', 'newf64', 'strlen', 'strget', 'strset',
	'intval', 'newbool', 'boolval', 'fltval', 'veclen', 'vecget', 'tblnext', 'tblmeta', 'tblget', 'tblset',
	'framelen', 'framefield', 'stackget', 'stacksize', 'fninfo')
-- names for the name section. std & co are otherwise only required while eval is built
for _, name in ipairs{ 'alloc', 'obj', 'util', 'stack', '_table', '_string', '_float', '_lex', 'rt', 'frame',
		'vm', 'env', 'jsapi', 'std', 'stdcoro', 'stddebug', 'stdmath' } do
	M.namefuncs(name .. '.', require(name))
end
local chunks = mod:compile()

-- output file is rt.wasm, or the first arg
io.open(... or 'rt.wasm', 'w'):write(table.unpack(chunks)):close()

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
import(_rt, 'echo', 'echoobj', 'sin', 'cos', 'tan',
	'asin', 'acos', 'atan', 'atan2', 'random', 'exp', 'log', 'pow')
export(_stack, 'tmppush', 'tmppop', 'tmpclear', 'nthtmp', 'stacklen')
export(_vm, 'init', 'eval')
export(_env, 'genesis', 'initPrelude')
export(_js, 'typeof', 'newstr', 'newtbl', 'newi64', 'newf64', 'strlen', 'strget', 'strset',
	'intval', 'fltval', 'veclen', 'vecget', 'tblnext', 'tblmeta', 'tblget', 'tblset')
local chunks = mod:compile()

io.open('rt.wasm', 'w'):write(table.unpack(chunks)):close()

#!/usr/bin/env lua
-- Builds scripts/comp.wasm: the lexer & compiler, for node to compile the prelude at build time
-- (rt.wasm can't be built yet, it holds the prelude's bytecode)
package.path = 'rt/?.lua;' .. package.path
local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local lparse = require 'lparse'
local _js = require 'jsapi'
local R, functy = alloc.R, alloc.functy

local mod = M.mod()
mod:export('compile', lparse.compile)
for _, k in ipairs{ 'code', 'line', 's', 'e', 'tok', 'n', 'n2', 'arg', 'arg2' } do
	mod:export('err' .. k, lparse.errs[k])
end
-- function object fields, for JS to write them out
local function fnget(name, field, ty, post)
	mod:export(name, func(V, ty, function(f, fn)
		f:load(fn)
		f:refcast(R.functy)
		if post then
			post(f)
		else
			f:structget(functy, field)
		end
	end))
end
fnget('fnparamc', 'paramc', i32)
fnget('fnlocalc', 'localc', i32)
fnget('fnisvarg', nil, i32, function(f) f:structget(functy, 'isdotdotdot', false) end)
fnget('fnbclen', nil, i32, function(f)
	f:structget(functy, 'bc')
	f:arraylen()
end)
fnget('fnnconst', nil, i32, function(f)
	f:structget(functy, 'consts')
	f:arraylen()
end)
mod:export('fnbcget', func(V, i32, i32, function(f, fn, i)
	f:load(fn)
	f:refcast(R.functy)
	f:structget(functy, 'bc')
	f:load(i)
	f:arrayget(alloc.bytes, false)
end))
mod:export('fnconst', func(V, i32, V, function(f, fn, i)
	f:load(fn)
	f:refcast(R.functy)
	f:structget(functy, 'consts')
	f:load(i)
	f:arrayget(alloc.vals)
end))
for _, name in ipairs{ 'typeof', 'newstr', 'newtbl', 'strlen', 'strget', 'strset', 'intval', 'fltval', 'boolval',
		'tblnext', 'tblget', 'fninfo' } do
	mod:export(name, _js[name])
end
M.namefuncs('lcode.', require 'lcode')
local chunks = mod:compile()

local out = ... or 'scripts/comp.wasm'
io.open(out, 'w'):write(table.unpack(chunks)):close()
M.depfile(out)

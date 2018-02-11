local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local vec, coro, newtbl, newcoro, newvecbuf = alloc.vec, alloc.coro, alloc.newtbl, alloc.newcoro, alloc.newvecbuf

local stack = require 'stack'
local nthtmp, tmppush, tmppop = stack.nthtmp, stack.tmppush, stack.tmppop

local _table = require '_table'
local tblget, tblset = _table.tblget, _table.tblset

local vm = require 'vm'

local addkv2env = func(i32, i32, void, function(f, k, v)
	f:call(param0)
	f:i32load(vec.base)
	f:load(k)
	f:load(v)
	f:call(tblset)
end)

local addkv2luwa = func(i32, i32, void, function(f, k, v)
	f:call(param0)
	f:i32load(vec.base + 4)
	f:load(k)
	f:load(v)
	f:call(tblset)
end)

local addkv2top = func(i32, i32, void, function(f, k, v)
	f:i32(4)
	f:call(nthtmp)
	f:load(k)
	f:load(v)
	f:call(tblset)
end)

local genesis = func(function(f)
	local a = f:locals(i32, 1)

	f:call(newcoro)
	f:storeg(oluastack)
	f:i32(32)
	f:call(newvecbuf)
	f:store(a)
	f:loadg(oluastack)
	f:load(a)
	f:i32store(coro.stack)
end)

local initPrelude = func(i32, function(f)
	local a = f:locals(i32)

	local function addfun(fn, ...)
		for i=1,select('#', ...),2 do
			local k, v = select(i, ...)
			f:i32(k)
			f:i32(v)
			f:call(fn)
		end
	end

	local function addmod(name, ...)
		if select('#', ...) == 0 then
			f:i32(name)
			f:call(newtbl)
			f:call(addkv2env)
		else
			f:call(newtbl)
			f:call(tmppush)
			for i=1,select('#', ...),2 do
				local k, v = select(i, ...)
				f:i32(k)
				f:i32(v)
				f:call(addkv2top)
			end
			f:i32(name)
			f:i32(4)
			f:call(nthtmp)
			f:call(addkv2env)
			f:call(tmppop)
		end
	end

	f:call(newtbl)
	f:call(tmppush)

	f:call(newtbl)
	f:call(tmppush)

	f:i32(GF.prelude0)
	f:call(vm.init)

	addfun(addkv2env,
		GS.error, GF.error,
		GS.next, GF.next,
		GS.pcall, GF.pcall,
		GS.rawget, GF.rawget,
		GS.rawset, GF.rawset,
		GS.select, GF.select,
		GS.type, GF.type)
	addfun(addkv2luwa,
		GS.lexgen, GF._lex,
		GS.astgen, GF.astgen0,
		GS.bcgen, GF.bcgen0,
		GS.lex, GF.lex0,
		GS.ast, GF.ast0,
		GS.bc, GF.bc0,
		GS.stdin, GF._stdin,
		GS.stdout, GF._stdout,
		GS.ioread, GF._ioread,
		GS.iowrite, GF._iowrite,
		GS.ioflush, GF._ioflush,
		GS.ioclose, GF._ioclose,
		GS.iosetvbuf, GF._iosetvbuf,
		GS.fn_set_localc, GF._fn_set_localc,
		GS.fn_set_paramc, GF._fn_set_paramc,
		GS.fn_set_isdotdotdot, GF._fn_set_isdotdotdot,
		GS.fn_set_bc, GF._fn_set_bc,
		GS.fn_set_frees, GF._fn_set_frees,
		GS.fn_set_consts, GF._fn_set_consts,
		GS.vec_new, GF._vec_new)

	addmod(GS.coroutine,
		GS.create, GF.coro_create,
		GS.resume, GF.coro_resume,
		GS.yield, GF.coro_yield,
		GS.running, GF.coro_running,
		GS.status, GF.coro_status)
	addmod(GS.debug,
		GS.getmetatable, GF.debug_getmetatable,
		GS.setmetatable, GF.debug_setmetatable)
	addmod(GS.io)
	addmod(GS.math,
		GS.type, GF.math_type)
	addmod(GS.os)
	addmod(GS.package)
	addmod(GS.string)
	addmod(GS.table)
	addmod(GS.utf8)

	f:call(param0)
	f:i32load(vec.base)
end)

return {
	genesis = genesis,
	initPrelude = initPrelude,
}
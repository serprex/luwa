local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local R, coro, newtbl, newcoro = alloc.R, alloc.coro, alloc.newtbl, alloc.newcoro

local stack = require 'stack'
local nthtmp, tmppush, tmppop = stack.nthtmp, stack.tmppush, stack.tmppop

local _table = require '_table'
local tblset = _table.tblset

local vm = require 'vm'
local rt = require 'rt'
local frame = require 'frame'

-- t[k] = v, t is param n of the prelude: 0 is _ENV, 1 is _luwa
local function addkv(n)
	return func(V, V, void, function(f, k, v)
		f:i32(n)
		f:call(frame.param)
		f:refcast(R.tbl)
		f:load(k)
		f:load(v)
		f:call(tblset)
	end)
end
local addkv2env = addkv(0)
local addkv2luwa = addkv(1)

-- top of stack[k] = v
local addkv2top = func(V, V, void, function(f, k, v)
	f:i32(1)
	f:call(nthtmp)
	f:refcast(R.tbl)
	f:load(k)
	f:load(v)
	f:call(tblset)
end)

-- Make the main coro & the static objects
local genesis = func(function(f)
	f:call(newcoro)
	f:storeg(oluastack)
	f:i32(64)
	f:call(alloc.newstack)
	f:storeg(gstack)
	f:loadg(oluastack)
	f:loadg(gstack)
	f:structset(coro, 'stack')
	-- the main coro is always running or normal
	f:loadg(oluastack)
	f:i32(alloc.corostate.live)
	f:structset(coro, 'state')
	f:call(rt.initstatics)
end)

-- Sets up the prelude to run, returns _ENV. eval then runs the prelude
local initPrelude = func(R.tbl, function(f)
	local function addfun(fn, ...)
		for i=1,select('#', ...),2 do
			local k, v = select(i, ...)
			f:loadg(k)
			f:loadg(v)
			f:call(fn)
		end
	end

	local function addmod(name, ...)
		if select('#', ...) == 0 then
			f:loadg(name)
			f:call(newtbl)
			f:call(addkv2env)
		else
			f:call(newtbl)
			f:call(tmppush)
			for i=1,select('#', ...),2 do
				local k, v = select(i, ...)
				f:loadg(k)
				f:loadg(v)
				f:call(addkv2top)
			end
			f:loadg(name)
			f:i32(1)
			f:call(nthtmp)
			f:call(addkv2env)
			f:call(tmppop)
			f:drop()
		end
	end

	f:call(newtbl)
	f:call(tmppush)

	f:call(newtbl)
	f:call(tmppush)

	f:loadg(GF.prelude0)
	f:call(vm.init)

	addfun(addkv2env,
		GS.error, GF.error,
		GS.next, GF.next,
		GS.pcall, GF.pcall,
		GS.xpcall, GF.xpcall,
		GS.rawget, GF.rawget,
		GS.rawset, GF.rawset,
		GS.select, GF.select,
		GS.type, GF.type,
		GS._VERSION, GS[rt.Version])
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
		GS.fn_new, GF._fn_new,
		GS.fn_set_localc, GF._fn_set_localc,
		GS.fn_set_paramc, GF._fn_set_paramc,
		GS.fn_set_isdotdotdot, GF._fn_set_isdotdotdot,
		GS.fn_set_bc, GF._fn_set_bc,
		GS.fn_set_frees, GF._fn_set_frees,
		GS.fn_set_consts, GF._fn_set_consts,
		GS.fn_set_info, GF._fn_set_info,
		GS.fn_info, GF._fn_info,
		GS.frame, GF._frame,
		GS.seterrfns, GF._seterrfns,
		GS.vec_new, GF._vec_new,
		GS.random, GF._random,
		GS.objid, GF._objid,
		GS.reinterp, GF._reinterp,
		GS.host, GF._host)

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
		GS.type, GF.math_type,
		GS.abs, GF.math_abs,
		GS.ceil, GF.math_ceil,
		GS.floor, GF.math_floor,
		GS.sin, GF.math_sin,
		GS.cos, GF.math_cos,
		GS.tan, GF.math_tan,
		GS.asin, GF.math_asin,
		GS.acos, GF.math_acos,
		GS.exp, GF.math_exp,
		GS.log, GF.math_log,
		GS.atan, GF.math_atan)
	addmod(GS.os)
	addmod(GS.package)
	addmod(GS.string,
		GS.byte, GF.string_byte,
		GS.char, GF.string_char,
		GS.sub, GF.string_sub)
	addmod(GS.table,
		GS.unpack, GF.table_unpack)
	addmod(GS.utf8)

	f:i32(0)
	f:call(frame.param)
	f:refcast(R.tbl)
end)

return {
	genesis = genesis,
	initPrelude = initPrelude,
}
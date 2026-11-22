-- Builtins written in wasm. Each reads its params with param(i) & pushes its results,
-- the builtin's bytecode then returns them
local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, R, typeof, str, bytes, vals, vec, tbl, functy, newi64 =
	alloc.types, alloc.R, alloc.typeof, alloc.str, alloc.bytes, alloc.vals, alloc.vec, alloc.tbl, alloc.functy, alloc.newi64

local stack = require 'stack'
local tmppush, extendtmp, stacklen, scopy = stack.tmppush, stack.extendtmp, stack.stacklen, stack.scopy

local _table = require '_table'
local _obj = require 'obj'

local util = require 'util'
local toint, inti64 = util.toint, util.inti64

local rt = require 'rt'
local frame = require 'frame'
local param, vargc, varg, getf = frame.param, frame.vargc, frame.varg, frame.getf

local function loadparam(f, i)
	f:i32(i)
	f:call(param)
end

-- TODO unwind to pcall. For now print the message & trap
local std_error = func(function(f)
	loadparam(f, 0)
	f:call(rt.echoobj)
	f:unreachable()
end)

-- next(t, k): the next key & value, or just nil at the end
local std_next = func(function(f)
	local k, v = f:locals(V, 2)
	loadparam(f, 0)
	f:refcast(R.tbl)
	loadparam(f, 1)
	f:call(_table.tblnext)
	f:store(v)
	f:tee(k)
	f:call(tmppush)
	f:load(k)
	f:refisnull()
	f:eqz()
	f:iff(function()
		f:load(v)
		f:call(tmppush)
	end)
end)

-- TODO needs error unwinding
local std_pcall = func(function(f)
	f:unreachable()
end)

local std_rawget = func(function(f)
	loadparam(f, 0)
	f:refcast(R.tbl)
	loadparam(f, 1)
	f:call(_table.tblget)
	f:call(tmppush)
end)

local std_rawset = func(function(f)
	loadparam(f, 0)
	f:refcast(R.tbl)
	loadparam(f, 1)
	loadparam(f, 2)
	f:call(_table.tblset)
end)

-- Integer value of param i, or dflt when it's nil. Traps when it isn't an integer
-- TODO raise an error once error unwinding works
local function intparam(f, i, dflt)
	local tmp = f:locals(V)
	loadparam(f, i)
	f:tee(tmp)
	f:refisnull()
	f:iff(i32, dflt, function()
		f:load(tmp)
		f:call(toint)
		f:tee(tmp)
		f:refisnull()
		f:iff(function()
			f:unreachable()
		end)
		f:load(tmp)
		f:call(inti64)
		f:i32wrap()
	end)
end

-- Is v the string "#"
local ishash = func(V, i32, function(f, v)
	local b = f:locals(R.bytes)
	f:load(v)
	f:call(typeof)
	f:i32(types.str)
	f:ne()
	f:iff(function()
		f:i32(0)
		f:ret()
	end)
	f:load(v)
	f:refcast(R.str)
	f:structget(str, 'bytes')
	f:tee(b)
	f:arraylen()
	f:i32(1)
	f:eq()
	f:iff(i32, function()
		f:load(b)
		f:i32(0)
		f:arrayget(bytes, false)
		f:i32(string.byte('#'))
		f:eq()
	end, function()
		f:i32(0)
	end)
end)

-- select('#', ...) pushes the vararg count. select(n, ...) pushes the varargs from n on,
-- negative n counts from the end
-- TODO bad n should raise an error, it traps for now
local std_select = func(function(f)
	local n, cnt, len = f:locals(i32, 3)
	f:call(vargc)
	f:store(cnt)
	loadparam(f, 0)
	f:call(ishash)
	f:iff(function()
		f:load(cnt)
		f:i64extendu()
		f:call(newi64)
		f:call(tmppush)
		f:ret()
	end)

	-- n = index of first vararg to return, from 0
	intparam(f, 0, function() f:unreachable() end)
	f:tee(n)
	f:i32(0)
	f:lts()
	f:iff(i32, function()
		f:load(cnt)
		f:load(n)
		f:add()
	end, function()
		f:load(n)
		f:i32(1)
		f:sub()
	end)
	f:tee(n)
	f:i32(0)
	f:lts()
	f:iff(function()
		f:unreachable()
	end)
	f:load(n)
	f:load(cnt)
	f:gts()
	f:iff(function()
		f:load(cnt)
		f:store(n)
	end)

	-- cnt = how many to copy
	f:load(cnt)
	f:load(n)
	f:sub()
	f:tee(cnt)
	f:iff(function()
		f:call(stacklen)
		f:store(len)
		f:load(cnt)
		f:call(extendtmp)
		f:load(len)
		getf(f, 'base')
		getf(f, 'dotdotdot')
		f:add()
		f:load(n)
		f:add()
		f:load(cnt)
		f:call(scopy)
	end)
end)

-- string.byte(s, i=1, j=i): push the bytes s[i..j] as integers. Negative i, j count from the end
local std_string_byte = func(function(f)
	local len, i, j = f:locals(i32, 3)
	local b = f:locals(R.bytes)

	loadparam(f, 0)
	f:call(typeof)
	f:i32(types.str)
	f:ne()
	f:iff(function()
		f:unreachable()
	end)
	loadparam(f, 0)
	f:refcast(R.str)
	f:structget(str, 'bytes')
	f:tee(b)
	f:arraylen()
	f:store(len)

	intparam(f, 1, function()
		f:i32(1)
	end)
	f:store(i)
	intparam(f, 2, function()
		f:load(i)
	end)
	f:store(j)

	-- negative: from the end
	f:load(i)
	f:i32(0)
	f:lts()
	f:iff(function()
		f:load(len)
		f:load(i)
		f:add()
		f:i32(1)
		f:add()
		f:store(i)
	end)
	f:load(j)
	f:i32(0)
	f:lts()
	f:iff(function()
		f:load(len)
		f:load(j)
		f:add()
		f:i32(1)
		f:add()
		f:store(j)
	end)
	-- clamp to 1..len
	f:load(i)
	f:i32(1)
	f:lts()
	f:iff(function()
		f:i32(1)
		f:store(i)
	end)
	f:load(j)
	f:load(len)
	f:gts()
	f:iff(function()
		f:load(len)
		f:store(j)
	end)

	f:block(function(done)
		f:loop(function(loop)
			f:load(i)
			f:load(j)
			f:gts()
			f:brif(done)
			f:load(b)
			f:load(i)
			f:i32(1)
			f:sub()
			f:arrayget(bytes, false)
			f:i64extendu()
			f:call(newi64)
			f:call(tmppush)
			f:load(i)
			f:i32(1)
			f:add()
			f:store(i)
			f:br(loop)
		end)
	end)
end)

-- string.char(...): string made of the given byte values
local std_string_char = func(function(f)
	local n, k = f:locals(i32, 2)
	local b = f:locals(R.bytes)
	local v = f:locals(V)

	f:call(vargc)
	f:tee(n)
	f:arraynewdefault(bytes)
	f:store(b)

	f:block(function(done)
		f:loop(function(loop)
			f:load(k)
			f:load(n)
			f:geu()
			f:brif(done)

			f:load(k)
			f:call(varg)
			f:call(toint)
			f:tee(v)
			f:refisnull()
			f:iff(function()
				f:unreachable()
			end)
			f:load(b)
			f:load(k)
			f:load(v)
			f:call(inti64)
			f:i32wrap()
			f:arrayset(bytes)

			f:load(k)
			f:i32(1)
			f:add()
			f:store(k)
			f:br(loop)
		end)
	end)

	f:load(b)
	f:call(alloc.strfrombytes)
	f:call(tmppush)
end)

-- _luwa.fn_new(): an empty function object, filled in by the fn_set_* calls
local std_fn_new = func(function(f)
	f:call(alloc.newfunc)
	f:call(tmppush)
end)

-- _luwa.fn_set_*(fn, x): set a field of fn. val leaves the value to store
local function fnset(field, val)
	return func(function(f)
		loadparam(f, 0)
		f:refcast(R.functy)
		val(f)
		f:structset(functy, field)
	end)
end
local std_fn_set_localc = fnset('localc', function(f)
	intparam(f, 1, function() f:i32(0) end)
end)
local std_fn_set_paramc = fnset('paramc', function(f)
	intparam(f, 1, function() f:i32(0) end)
end)
local std_fn_set_isdotdotdot = fnset('isdotdotdot', function(f)
	loadparam(f, 1)
	f:call(_obj.truthy)
end)
local std_fn_set_bc = fnset('bc', function(f)
	loadparam(f, 1)
	f:refcast(R.str)
	f:structget(str, 'bytes')
end)
local function vecarr(f)
	loadparam(f, 1)
	f:refcast(R.vec)
	f:structget(vec, 'arr')
end
local std_fn_set_frees = fnset('frees', vecarr)
local std_fn_set_consts = fnset('consts', vecarr)

-- _luwa.vec_new(...): a vec holding the args
local std_vec_new = func(function(f)
	local n = f:locals(i32)
	local arr = f:locals(R.vals)
	f:call(vargc)
	f:tee(n)
	f:arraynewdefault(vals)
	f:tee(arr)
	f:i32(0)
	f:loadg(gstack)
	f:structget(alloc.stack, 'arr')
	getf(f, 'base')
	getf(f, 'dotdotdot')
	f:add()
	f:load(n)
	f:arraycopy(vals, vals)
	f:i32(types.vec)
	f:load(arr)
	f:refasnonnull()
	f:structnew(vec)
	f:call(tmppush)
end)

local std_type = func(function(f)
	local a = f:locals(V)
	f:block(R.str, function(res)
		f:switch(function()
			loadparam(f, 0)
			f:tee(a)
			f:call(typeof)
		end, types.int, types.float, function()
			f:loadg(GS.number)
			f:br(res)
		end, types.single, function()
			f:load(a)
			f:refisnull()
			f:iff(R.str, function()
				f:loadg(GS['nil'])
			end, function()
				f:loadg(GS.boolean)
			end)
			f:br(res)
		end, types.tbl, function()
			f:loadg(GS.table)
			f:br(res)
		end, types.str, function()
			f:loadg(GS.string)
			f:br(res)
		end, types.vec, types.buf, function()
			f:loadg(GS.userdata)
			f:br(res)
		end, types.functy, function()
			f:loadg(GS['function'])
			f:br(res)
		end, types.coro)
		f:loadg(GS.thread)
	end)
	f:call(tmppush)
end)

-- _luwa.lexgen(src): token string & value vec
local std_lexgen = func(function(f)
	local vs = f:locals(R.vec)
	loadparam(f, 0)
	f:refcast(R.str)
	f:call(require('_lex').lex)
	f:store(vs)
	f:call(tmppush)
	f:load(vs)
	f:call(tmppush)
end)

return {
	error = std_error,
	next = std_next,
	pcall = std_pcall,
	rawget = std_rawget,
	rawset = std_rawset,
	select = std_select,
	type = std_type,
	string_byte = std_string_byte,
	string_char = std_string_char,
	fn_new = std_fn_new,
	fn_set_localc = std_fn_set_localc,
	fn_set_paramc = std_fn_set_paramc,
	fn_set_isdotdotdot = std_fn_set_isdotdotdot,
	fn_set_bc = std_fn_set_bc,
	fn_set_frees = std_fn_set_frees,
	fn_set_consts = std_fn_set_consts,
	vec_new = std_vec_new,
	lexgen = std_lexgen,
}

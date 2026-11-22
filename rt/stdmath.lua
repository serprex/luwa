local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, typeof, int, float, newi64, newf64 = alloc.types, alloc.typeof, alloc.int, alloc.float, alloc.newi64, alloc.newf64

local stack = require 'stack'
local tmppush = stack.tmppush

local rt = require 'rt'

local util = require 'util'
local tonum, numf64 = util.tonum, util.numf64

local frame = require 'frame'
local param = frame.param

-- Param i, trapping unless it's a number
-- TODO raise an error once error unwinding works
local function numparam(f, i)
	local a = f:locals(V)
	f:i32(i)
	f:call(param)
	f:call(tonum)
	f:tee(a)
	f:refisnull()
	f:iff(function()
		f:unreachable()
	end)
	f:load(a)
end

local math_abs = func(function(f)
	local a = f:locals(V)
	local a64 = f:locals(i64)
	numparam(f, 0)
	f:tee(a)
	f:call(typeof)
	f:i32(types.int)
	f:eq()
	f:iff(V, function()
		f:load(a)
		f:refcast(M.ref(int))
		f:structget(int, 'val')
		f:tee(a64)
		f:i64(0)
		f:lts()
		f:iff(V, function()
			f:i64(0)
			f:load(a64)
			f:sub()
			f:call(newi64)
		end, function()
			f:load(a)
		end)
	end, function()
		f:load(a)
		f:refcast(M.ref(float))
		f:structget(float, 'val')
		f:abs()
		f:call(newf64)
	end)
	f:call(tmppush)
end)

local function genmathround(op)
	return func(function(f)
		local a = f:locals(V)
		numparam(f, 0)
		f:tee(a)
		f:call(typeof)
		f:i32(types.float)
		f:eq()
		f:iff(V, function()
			f:load(a)
			f:refcast(M.ref(float))
			f:structget(float, 'val')
			f[op](f)
			f:i64truncs()
			f:call(newi64)
		end, function()
			f:load(a)
		end)
		f:call(tmppush)
	end)
end

local math_ceil = genmathround('ceil')
local math_floor = genmathround('floor')

local function genmathmath(fn)
	return func(function(f)
		numparam(f, 0)
		f:call(numf64)
		f:call(fn)
		f:call(newf64)
		f:call(tmppush)
	end)
end

local math_sin = genmathmath(rt.sin)
local math_cos = genmathmath(rt.cos)
local math_tan = genmathmath(rt.tan)
local math_asin = genmathmath(rt.asin)
local math_acos = genmathmath(rt.acos)
local math_exp = genmathmath(rt.exp)

-- log(x, base): base is optional
local math_log = func(function(f)
	f:i32(1)
	f:call(param)
	f:refisnull()
	f:iff(f64, function()
		numparam(f, 0)
		f:call(numf64)
		f:call(rt.log)
	end, function()
		numparam(f, 0)
		f:call(numf64)
		f:call(rt.log)
		numparam(f, 1)
		f:call(numf64)
		f:call(rt.log)
		f:div()
	end)
	f:call(newf64)
	f:call(tmppush)
end)

-- atan(y, x): x is optional
local math_atan = func(function(f)
	f:i32(1)
	f:call(param)
	f:refisnull()
	f:iff(f64, function()
		numparam(f, 0)
		f:call(numf64)
		f:call(rt.atan)
	end, function()
		numparam(f, 0)
		f:call(numf64)
		numparam(f, 1)
		f:call(numf64)
		f:call(rt.atan2)
	end)
	f:call(newf64)
	f:call(tmppush)
end)

local math_type = func(function(f)
	f:block(V, function(res)
		f:switch(function()
			f:i32(0)
			f:call(param)
			f:call(typeof)
		end, types.int, function()
			f:loadg(GS.integer)
			f:br(res)
		end, types.float, function()
			f:loadg(GS.float)
			f:br(res)
		end, -1)
		f:refnull(M.heap.eq)
	end)
	f:call(tmppush)
end)

return {
	math_abs = math_abs,
	math_asin = math_asin,
	math_acos = math_acos,
	math_atan = math_atan,
	math_exp = math_exp,
	math_sin = math_sin,
	math_cos = math_cos,
	math_tan = math_tan,
	math_log = math_log,
	math_floor = math_floor,
	math_ceil = math_ceil,
	math_type = math_type,
}

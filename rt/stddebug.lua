local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, R, typeof, tbl = alloc.types, alloc.R, alloc.typeof, alloc.tbl

local stack = require 'stack'
local tmppush = stack.tmppush

local frame = require 'frame'
local param, getmeta = frame.param, frame.getmeta

-- TODO metatables for every type
local debug_getmetatable = func(function(f)
	f:i32(0)
	f:call(param)
	f:call(getmeta)
	f:call(tmppush)
end)

-- debug.setmetatable(v, mt): tables & strings only, mt must be a table or nil
local debug_setmetatable = func(function(f)
	local ty = f:locals(i32)
	f:i32(1)
	f:call(param)
	f:call(typeof)
	f:i32(types.tbl)
	f:ne()
	f:i32(1)
	f:call(param)
	f:refisnull()
	f:eqz()
	f:band()
	f:iff(function()
		f:unreachable()
	end)
	f:i32(0)
	f:call(param)
	f:call(typeof)
	f:tee(ty)
	f:i32(types.tbl)
	f:eq()
	f:iff(function()
		f:i32(0)
		f:call(param)
		f:refcast(R.tbl)
		f:i32(1)
		f:call(param)
		f:refcast(R.tbl)
		f:structset(tbl, 'meta')
		f:ret()
	end)
	f:load(ty)
	f:i32(types.str)
	f:eq()
	f:iff(function()
		f:i32(1)
		f:call(param)
		f:refcast(R.tbl)
		f:storeg(ostrmt)
		f:ret()
	end)
	f:unreachable()
end)

return {
	debug_getmetatable = debug_getmetatable,
	debug_setmetatable = debug_setmetatable,
}

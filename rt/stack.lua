-- The running coro's Lua value stack & call frames, both growable.
-- Positions are slot numbers from 0. Slots at or past len are always nil
local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local stack, frames, vals, i32s, R = alloc.stack, alloc.frames, alloc.vals, alloc.i32s, alloc.R

-- The running coro's stack & frames, kept here so ops needn't go through the coro
gstack = M.global(R.stack, true)
gframes = M.global(R.frames, true)

-- Make room for n more slots
local reserve = func(i32, void, function(f, n)
	local arr, narr = f:locals(R.vals, 2)
	local need, cap = f:locals(i32, 2)
	f:loadg(gstack)
	f:structget(stack, 'len')
	f:load(n)
	f:add()
	f:tee(need)
	f:loadg(gstack)
	f:structget(stack, 'arr')
	f:tee(arr)
	f:arraylen()
	f:tee(cap)
	f:gtu()
	f:iff(function()
		-- cap = max(cap*2, need)
		f:load(cap)
		f:i32(1)
		f:shl()
		f:tee(cap)
		f:load(need)
		f:load(cap)
		f:load(need)
		f:gtu()
		f:select()
		f:arraynewdefault(vals)
		f:tee(narr)
		f:i32(0)
		f:load(arr)
		f:i32(0)
		f:load(arr)
		f:arraylen()
		f:arraycopy(vals, vals)
		f:loadg(gstack)
		f:load(narr)
		f:refasnonnull()
		f:structset(stack, 'arr')
	end)
end)

local tmppush = func(V, void, function(f, o)
	local n = f:locals(i32)
	f:i32(1)
	f:call(reserve)
	f:loadg(gstack)
	f:structget(stack, 'arr')
	f:loadg(gstack)
	f:structget(stack, 'len')
	f:tee(n)
	f:load(o)
	f:arrayset(vals)
	f:loadg(gstack)
	f:load(n)
	f:i32(1)
	f:add()
	f:structset(stack, 'len')
end)

local tmppop = func(V, function(f)
	local n = f:locals(i32)
	local arr = f:locals(R.vals)
	f:loadg(gstack)
	f:structget(stack, 'arr')
	f:tee(arr)
	f:loadg(gstack)
	f:structget(stack, 'len')
	f:i32(1)
	f:sub()
	f:tee(n)
	f:arrayget(vals)
	f:load(arr)
	f:load(n)
	f:refnull(M.heap.eq)
	f:arrayset(vals)
	f:loadg(gstack)
	f:load(n)
	f:structset(stack, 'len')
end)

local stacklen = func(i32, function(f)
	f:loadg(gstack)
	f:structget(stack, 'len')
end)

-- Shrink to n slots
local setstacklen = func(i32, void, function(f, n)
	local len = f:locals(i32)
	f:loadg(gstack)
	f:structget(stack, 'len')
	f:tee(len)
	f:load(n)
	f:gtu()
	f:iff(function()
		f:loadg(gstack)
		f:structget(stack, 'arr')
		f:load(n)
		f:refnull(M.heap.eq)
		f:load(len)
		f:load(n)
		f:sub()
		f:arrayfill(vals)
		f:loadg(gstack)
		f:load(n)
		f:structset(stack, 'len')
	end)
end)

local tmpclear = func(function(f)
	f:i32(0)
	f:call(setstacklen)
end)

-- Add n nils
local extendtmp = func(i32, void, function(f, n)
	f:load(n)
	f:call(reserve)
	f:loadg(gstack)
	f:loadg(gstack)
	f:structget(stack, 'len')
	f:load(n)
	f:add()
	f:structset(stack, 'len')
end)

-- Slot i
local sget = func(i32, V, function(f, i)
	f:loadg(gstack)
	f:structget(stack, 'arr')
	f:load(i)
	f:arrayget(vals)
end)
local sset = func(i32, V, void, function(f, i, v)
	f:loadg(gstack)
	f:structget(stack, 'arr')
	f:load(i)
	f:load(v)
	f:arrayset(vals)
end)

-- nth value from the top, 1 is the top
local nthtmp = func(i32, V, function(f, i)
	f:call(stacklen)
	f:load(i)
	f:sub()
	f:call(sget)
end)
local setnthtmp = func(V, i32, void, function(f, v, i)
	f:call(stacklen)
	f:load(i)
	f:sub()
	f:load(v)
	f:call(sset)
end)

-- Copy n slots from src to dst, they may overlap
local scopy = func(i32, i32, i32, void, function(f, dst, src, n)
	local arr = f:locals(R.vals)
	f:loadg(gstack)
	f:structget(stack, 'arr')
	f:tee(arr)
	f:load(dst)
	f:load(arr)
	f:load(src)
	f:load(n)
	f:arraycopy(vals, vals)
end)

-- Call frames: 8 i32s each
local df = {
	type = 0, -- calltypes
	pc = 1,
	base = 2, -- slot of param 0. The function is at base-1
	dotdotdot = 3, -- base+dotdotdot = first vararg. They end at base+locals
	retb = 4, -- base+retb = where return values go
	retc = 5, -- how many values to return, 0xffff for all of them
	locals = 6, -- base+locals = first local
	frame = 7, -- base+frame = objframe: bc, consts, frees
	sizeof = 8,
}

-- Index of the top frame's first field
local ftop = func(i32, function(f)
	f:loadg(gframes)
	f:structget(frames, 'len')
	f:i32(df.sizeof)
	f:sub()
end)
local fget = func(i32, i32, function(f, field)
	f:loadg(gframes)
	f:structget(frames, 'arr')
	f:call(ftop)
	f:load(field)
	f:add()
	f:arrayget(i32s)
end)
local fset = func(i32, i32, void, function(f, field, v)
	f:loadg(gframes)
	f:structget(frames, 'arr')
	f:call(ftop)
	f:load(field)
	f:add()
	f:load(v)
	f:arrayset(i32s)
end)
-- Push a zeroed frame
local fpush = func(function(f)
	local arr, narr = f:locals(R.i32s, 2)
	local len = f:locals(i32)
	f:loadg(gframes)
	f:structget(frames, 'len')
	f:tee(len)
	f:i32(df.sizeof)
	f:add()
	f:loadg(gframes)
	f:structget(frames, 'arr')
	f:tee(arr)
	f:arraylen()
	f:gtu()
	f:iff(function()
		f:load(len)
		f:i32(1)
		f:shl()
		f:i32(df.sizeof * 4)
		f:add()
		f:arraynewdefault(i32s)
		f:tee(narr)
		f:i32(0)
		f:load(arr)
		f:i32(0)
		f:load(len)
		f:arraycopy(i32s, i32s)
		f:loadg(gframes)
		f:load(narr)
		f:refasnonnull()
		f:structset(frames, 'arr')
		f:loadg(gframes)
		f:structget(frames, 'arr')
		f:store(arr)
	end)
	f:load(arr)
	f:load(len)
	f:i32(0)
	f:i32(df.sizeof)
	f:arrayfill(i32s)
	f:loadg(gframes)
	f:load(len)
	f:i32(df.sizeof)
	f:add()
	f:structset(frames, 'len')
end)
local fpop = func(function(f)
	f:loadg(gframes)
	f:loadg(gframes)
	f:structget(frames, 'len')
	f:i32(df.sizeof)
	f:sub()
	f:structset(frames, 'len')
end)

return {
	reserve = reserve,
	tmppush = tmppush,
	tmppop = tmppop,
	tmpclear = tmpclear,
	stacklen = stacklen,
	setstacklen = setstacklen,
	extendtmp = extendtmp,
	sget = sget,
	sset = sset,
	nthtmp = nthtmp,
	setnthtmp = setnthtmp,
	scopy = scopy,
	df = df,
	ftop = ftop,
	fget = fget,
	fset = fset,
	fpush = fpush,
	fpop = fpop,
}

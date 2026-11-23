-- Small exports so JS can make & look at values. JS holds refs directly, the engine keeps them alive
local M = require 'make'
local func = M.func

local alloc = require 'alloc'
require 'stack' -- gframes & gstack
local R, str, bytes, int, float, vec = alloc.R, alloc.str, alloc.bytes, alloc.int, alloc.float, alloc.vec

local strlen = func(V, i32, function(f, s)
	f:load(s)
	f:refcast(R.str)
	f:structget(str, 'bytes')
	f:arraylen()
end)
local strget = func(V, i32, i32, function(f, s, i)
	f:load(s)
	f:refcast(R.str)
	f:structget(str, 'bytes')
	f:load(i)
	f:arrayget(bytes, false)
end)
-- Strings are only changed before anything else sees them, by newstr's caller
local strset = func(V, i32, i32, void, function(f, s, i, b)
	f:load(s)
	f:refcast(R.str)
	f:structget(str, 'bytes')
	f:load(i)
	f:load(b)
	f:arrayset(bytes)
end)
local intval = func(V, i64, function(f, x)
	f:load(x)
	alloc.intvalst(f)
end)
-- JS bool to false or true, & back
local newbool = func(i32, V, function(f, x)
	f:load(x)
	alloc.lbool(f)
end)
local boolval = func(V, i32, function(f, x)
	f:load(x)
	alloc.ltrue(f)
	f:refeq()
end)
local fltval = func(V, f64, function(f, x)
	f:load(x)
	f:refcast(M.ref(float))
	f:structget(float, 'val')
end)
local veclen = func(V, i32, function(f, x)
	f:load(x)
	f:refcast(R.vec)
	f:structget(vec, 'arr')
	f:arraylen()
end)
local vecget = func(V, i32, V, function(f, x, i)
	f:load(x)
	f:refcast(R.vec)
	f:structget(vec, 'arr')
	f:load(i)
	f:arrayget(alloc.vals)
end)
local tblnext = func(V, V, { V, V }, function(f, t, k)
	f:load(t)
	f:refcast(R.tbl)
	f:load(k)
	f:call(require('_table').tblnext)
end)
local tblmeta = func(V, V, function(f, t)
	f:load(t)
	f:refcast(R.tbl)
	f:structget(alloc.tbl, 'meta')
end)
local tblget = func(V, V, V, function(f, t, k)
	f:load(t)
	f:refcast(R.tbl)
	f:load(k)
	f:call(require('_table').tblget)
end)
local tblset = func(V, V, V, void, function(f, t, k, v)
	f:load(t)
	f:refcast(R.tbl)
	f:load(k)
	f:load(v)
	f:call(require('_table').tblset)
end)

-- The running coro's frames & stack, for a Lua traceback when wasm traps (rt.js)
local framelen = func(i32, function(f)
	f:loadg(gframes)
	f:structget(alloc.frames, 'len')
	f:i32(8)
	f:divu()
end)
-- field of frame n from the top, fields are stack.lua's df
local framefield = func(i32, i32, i32, function(f, n, field)
	f:loadg(gframes)
	f:structget(alloc.frames, 'arr')
	f:loadg(gframes)
	f:structget(alloc.frames, 'len')
	f:load(n)
	f:i32(1)
	f:add()
	f:i32(8)
	f:mul()
	f:sub()
	f:load(field)
	f:add()
	f:arrayget(alloc.i32s)
end)
local stackget = func(i32, V, function(f, i)
	f:loadg(gstack)
	f:structget(alloc.stack, 'arr')
	f:load(i)
	f:arrayget(alloc.vals)
end)
local stacksize = func(i32, function(f)
	f:loadg(gstack)
	f:structget(alloc.stack, 'len')
end)
-- a function's info table from load, nil for anything else
local fninfo = func(V, V, function(f, fn)
	f:load(fn)
	f:call(alloc.typeof)
	f:i32(alloc.types.functy)
	f:eq()
	f:iff(V, function()
		f:load(fn)
		f:refcast(R.functy)
		f:structget(alloc.functy, 'info')
	end, function()
		f:refnull(M.heap.eq)
	end)
end)

-- For rt.js's JIT: give a function its code
local jitset = func(R.functy, R.jitfty, void, function(f, fn, code)
	f:load(fn)
	f:structget(alloc.functy, 'jit')
	f:load(code)
	f:structset(alloc.jitcell, 'code')
end)

return {
	jitset = jitset,
	framelen = framelen,
	framefield = framefield,
	stackget = stackget,
	stacksize = stacksize,
	fninfo = fninfo,
	typeof = alloc.typeof,
	newstr = alloc.newstr,
	newtbl = alloc.newtbl,
	newi64 = alloc.newi64,
	newf64 = alloc.newf64,
	strlen = strlen,
	strget = strget,
	strset = strset,
	intval = intval,
	newbool = newbool,
	boolval = boolval,
	fltval = fltval,
	veclen = veclen,
	vecget = vecget,
	tblnext = tblnext,
	tblmeta = tblmeta,
	tblget = tblget,
	tblset = tblset,
}

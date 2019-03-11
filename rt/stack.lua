local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local buf, coro, vec = alloc.buf, alloc.coro, alloc.vec

local util = require 'util'
local extendvec, pushvec = util.extendvec, util.pushvec

local tmppush = func(i32, void, function(f, o)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:load(o)
	f:call(pushvec)
	f:drop()
end)

local tmppop = func(function(f)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:call(util.popvec)
	f:drop()
end)

local tmpclear = func(function(f)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32(0)
	f:i32store(buf.len)
end)

local nthbuf = func(i32, i32, i32, function(f, v, n)
	f:load(v)
	f:i32load(buf.ptr)
	f:load(v)
	f:i32load(buf.len)
	f:load(n)
	f:sub()
	f:add()
	f:i32load(vec.base)
end)

local setnthbuf = func(i32, i32, i32, void, function(f, o, v, n)
	f:load(v)
	f:i32load(buf.ptr)
	f:load(v)
	f:i32load(buf.len)
	f:load(n)
	f:sub()
	f:add()
	f:load(o)
	f:i32store(vec.base)
end)

local nthtmp = func(i32, i32, function(f, i)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:load(i)
	f:call(nthbuf)
end)

local setnthtmp = func(i32, i32, void, function(f, nv, i)
	f:load(nv)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:load(i)
	f:call(setnthbuf)
end)

local extendtmp = func(i32, void, function(f, amt)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:load(amt)
	f:call(extendvec)
	f:drop()
end)

local endofbuf = func(i32, i32, function(f, b)
	f:load(b)
	f:i32load(buf.ptr)
	f:load(b)
	f:i32load(buf.len)
	f:add()
end)

return {
	tmppush = tmppush,
	tmppop = tmppop,
	tmpclear = tmpclear,
	nthtmp = nthtmp,
	setnthtmp = setnthtmp,
	extendtmp = extendtmp,
	endofbuf = endofbuf,
	nthbuf = nthbuf,
	setnthbuf = setnthbuf,
}

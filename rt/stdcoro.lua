local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, R, typeof, coro, corostate = alloc.types, alloc.R, alloc.typeof, alloc.coro, alloc.corostate

local stack = require 'stack'
local tmppush = stack.tmppush

local frame = require 'frame'
local param = frame.param

-- TODO coroutines: create, resume & yield need to switch stacks
local coro_create = func(function(f)
	f:unreachable()
end)
local coro_resume = func(function(f)
	f:unreachable()
end)
local coro_yield = func(function(f)
	f:unreachable()
end)

-- running(): the running coro, & whether it's the main one
local coro_running = func(function(f)
	f:loadg(oluastack)
	f:call(tmppush)
	f:loadg(oluastack)
	f:structget(coro, 'caller')
	f:refisnull()
	f:refi31()
	f:call(tmppush)
end)

local coro_status = func(function(f)
	local a = f:locals(V)
	f:i32(0)
	f:call(param)
	f:tee(a)
	f:call(typeof)
	f:i32(types.coro)
	f:ne()
	f:iff(function()
		-- error
		f:unreachable()
	end)
	f:block(R.str, function(res)
		f:switch(function()
			f:load(a)
			f:refcast(R.coro)
			f:structget(coro, 'state', false)
		end, corostate.dead, function()
			f:loadg(GS.dead)
			f:br(res)
		end, corostate.norm, function()
			f:loadg(GS.normal)
			f:br(res)
		end, corostate.live, function()
			f:loadg(GS.running)
			f:br(res)
		end, corostate.wait)
		f:loadg(GS.suspended)
	end)
	f:call(tmppush)
end)

return {
	coro_create = coro_create,
	coro_resume = coro_resume,
	coro_yield = coro_yield,
	coro_running = coro_running,
	coro_status = coro_status,
}

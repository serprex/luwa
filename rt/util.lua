local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, typeof, int, float = alloc.types, alloc.typeof, alloc.int, alloc.float

-- x if it's a number, else nil
-- TODO strings that look like numbers
local tonum = func(V, V, function(f, x)
	f:load(x)
	f:call(typeof)
	f:i32(types.float)
	f:leu()
	f:iff(V, function()
		f:load(x)
	end, function()
		f:refnull(M.heap.eq)
	end)
end)

-- x as an int object if it has an integer value, else nil
local toint = func(V, V, function(f, x)
	local fl = f:locals(f64)
	f:switch(function()
		f:load(x)
		f:call(typeof)
	end, types.int, function()
		f:load(x)
		f:ret()
	end, types.float, function()
		f:load(x)
		f:refcast(M.ref(float))
		f:structget(float, 'val')
		f:tee(fl)
		f:load(fl)
		f:trunc()
		f:eq()
		f:iff(function()
			f:load(fl)
			f:i64truncs()
			f:call(alloc.newi64)
			f:ret()
		end)
	end, -1)
	f:refnull(M.heap.eq)
end)

-- A number's value as a float. x must be a number
local numf64 = func(V, f64, function(f, x)
	f:load(x)
	f:call(typeof)
	f:i32(types.int)
	f:eq()
	f:iff(f64, function()
		f:load(x)
		f:refcast(M.ref(int))
		f:structget(int, 'val')
		f:f64converts()
	end, function()
		f:load(x)
		f:refcast(M.ref(float))
		f:structget(float, 'val')
	end)
end)

-- An int's value. x must be an int
local inti64 = func(V, i64, function(f, x)
	f:load(x)
	f:refcast(M.ref(int))
	f:structget(int, 'val')
end)

return {
	tonum = tonum,
	toint = toint,
	numf64 = numf64,
	inti64 = inti64,
}

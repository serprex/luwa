pcall = func(i32, i32, i32, i32, function(f, stack)
	-- > func, p1, p2, ...
	-- < true, p1, p2, ...
	-- modify datastack: 2, 0, framesz, retc, base+1
	f:load(stack)
	f:i32load(buf.ptr)
	f:load(base)
	f:add()
	f:i32(TRUE)
	f:i32store(vec.base)

	f:loadg(odatastack)
	f:loadg(odatastacklen)
	f:add()
	f:i32(0)
	f:i32store(vec.base - 4)

	f:loadg(odatastack)
	f:loadg(odatastacklen)
	f:add()
	f:load(base)
	f:i32(1)
	f:add()
	f:i32store(vec.base - 8)

	f:loadg(odatastack)
	f:loadg(odatastacklen)
	f:add()
	f:i32(12)
	f:sub()
	f:load(retc)
	f:i32store(vec.base)

	f:loadg(odatastack)
	f:loadg(odatastacklen)
	f:add()
	f:i32(16)
	f:sub()
	f:i32(0)
	f:i32store(vec.base)

	f:loadg(odatastack)
	f:loadg(odatastacklen)
	f:add()
	f:i32(17)
	f:i32(2)
	f:i32store8(vec.base)

	f:i32(0)
end)

math_frexp = func(i32, function(f)
	-- TODO come up with a DRY type checking strategy
	-- TODO update ABI
	f:i32(4)
	f:call(nthtmp)
	f:f64load(num.val)
	f:call(frexp)
	-- Replace param x with ret of frexp
	-- 2nd retval is already in place
	f:call(newf64)
	f:i32(8)
	f:call(setnthtmp)
	f:i32(0)
end)

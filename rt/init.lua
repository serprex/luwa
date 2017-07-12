NIL = 0
TRUE = 8
FALSE = 16
HEAPBASE = 24
otmp = global(i32, true)
otmpstack = global(i32, true)
otmpstacklen = global(i32, true)
heaptip = global(i32, true, HEAPBASE)
markbit = global(i32, true)

data(0, 0, {
	-- nil
	0, 0, 0, 0, 2, 0, 0, 0,
	-- false
	0, 0, 0, 0, 3, 0, 0 ,0,
	-- true
	0, 0, 0, 0, 3, 1, 0, 0,
})

init = start(func(function(f)
	f:i32(32)
	f:call(newvec)
	f:storeg(otmpstack)
end))

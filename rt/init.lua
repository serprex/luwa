NIL = 0
TRUE = 8
FALSE = 16
HEAPBASE = 24
otmp = global(i32, true)
otmpstack = global(i32, true, HEAPBASE)
otmpstacklen = global(i32, true)
heaptip = global(i32, true, HEAPBASE + 48) -- 48 == allocsize(vec.base + 32)
markbit = global(i32, true)

data(0, 0, {
	-- nil
	0, 0, 0, 0, 2, 0, 0, 0,
	-- false
	0, 0, 0, 0, 3, 0, 0 ,0,
	-- true
	0, 0, 0, 0, 3, 1, 0, 0,
	-- otmpstack = vec(32)
	0, 0, 0, 0, 6, 32, -- 35 zeroes
})

NIL = 0
TRUE = 8
FALSE = 16
HEAPBASE = 24
otmp = global(i32, true)
oluastack = global(i32, true) -- default to NIL
heaptip = global(i32, true, HEAPBASE)
markbit = global(i32, true)
idcount = global(i32, true)

memory = importmemory('', 'm', 1)

--[[TODO
Builtin's need these strings as global constants:
(some may only be needed for compare-- may specialize)
math.type: float integer
corountine.status: running suspended normal dead
type: nil number string boolean table function thread userdata
select: #
load: b t bt
gc: collect stop restart count step setpause setstepmul isrunning
os.execute: exit, signal
io.seek: set cur end
io.setvbuf: no full line
io.type: file 'closed file'
io.read: n a l L
io.open: r w r+ w+ a+
metamethods: index newindex mode call metatable tostring len gc eq lt le
metamath: unm add sub mul div idiv mod pow concat band bor bxor bnot bshl bshr
]]

data(memory, 4, {
	-- nil
	2, 0, 0, 0,
	-- false
	0, 0, 0, 0, 3, 0, 0 ,0,
	-- true
	0, 0, 0, 0, 3, 1, 0, 0,
})

igcfix = importfunc('', 'gcfix')
igcmark = importfunc('', 'gcmark')
echo = importfunc('', 'echo', i32, i32)

setluastack = export('setluastack', func(i32, void, function(f, x)
	f:load(x)
	f:storeg(oluastack)
end))
getluastack = export('getluastack', func(i32, function(f)
	f:loadg(oluastack)
end))

echodrop = func(i32, void, function(f, x)
	f:load(x)
	f:call(echo)
	f:drop()
end)

echodrop2 = func(i32, i32, i32, function(f, x, y)
	f:load(x)
	f:load(y)
	f:call(echodrop)
	f:call(echo)
end)

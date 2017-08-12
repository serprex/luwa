NIL = 0
TRUE = 8
FALSE = 16
otmp = global(i32, true)
oluastack = global(i32, true) -- default to NIL
markbit = global(i32, true)
idcount = global(i32, true)

memory = importmemory('', 'm', 1)

--[[TODO
corountine.status: running suspended normal dead
type: nil number string boolean table function thread userdata
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

GS = {}
local function addStrings(base, mem, ...)
	for i = 1,select('#', ...) do
		local s = select(i, ...)
		GS[s] = base + #mem
		for j = 1,4 do
			mem[#mem+1] = 0
		end
		mem[#mem+1] = types.str
		for j = 0,24,8 do
			mem[#mem+1] = #s >> j & 255
		end
		for j = 1,4 do
			mem[#mem+1] = 0
		end
		for j = 1,#s do
			mem[#mem+1] = string.byte(s, j)
		end
		for j = #s+1,allocsizef(str.base + #s)-str.base do
			mem[#mem+1] = 0
		end
	end
	HEAPBASE = base + #mem
	return base, mem
end

data(memory, addStrings(4, {
	-- nil
	2, 0, 0, 0,
	-- false
	0, 0, 0, 0, 3, 0, 0 ,0,
	-- true
	0, 0, 0, 0, 3, 1, 0, 0,
}, 'float', 'integer', 'normal', 'suspended', 'running', 'dead', 'file', 'closed file',
	'nil', 'number', 'string', 'boolean', 'table', 'function', 'thread', 'userdata',
	'b', 't', 'bt', 'n', 'a', 'l', 'L', 'r', 'w', 'r+', 'w+', 'a+',
	'set', 'cur', 'end', 'no', 'full', 'line', 'exit', 'signal',
	'collect', 'stop', 'restart', 'count', 'step', 'setpause', 'setstepmul', 'isrunning',
	'__eq', '__lt', '__le', '__gt', '__ge', '__len', '__tostring', '__metatable',
	'__index', '__newindex', '__mode', '__call', '__unm', '__concat',
	'__add', '__sub', '__mul', '__div', '__idiv', '_mod', '__pow',
	'__bnot', '__band', '__bor', '__bxor', '__bshl', '__bshr'))

heaptip = global(i32, true, HEAPBASE)

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

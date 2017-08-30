NIL = 0
TRUE = 8
FALSE = 16
otmp = global(i32, true)
oluastack = global(i32, true) -- default to NIL
ostrmt = global(i32, true)
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
GF = {}
local function addString(mem, s)
	mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4],mem[#mem+5] = 0,0,0,0,types.str
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
local function addStatics(base, mem, ...)
	local fid = 0
	for i = 1,select('#', ...) do
		local s, sbase = select(i, ...), base + #mem
		if type(s) == 'string' then
			GS[s] = sbase
			addString(mem, s)
		else -- { funcname, paramc, isdotdotdot, bc }
			fid = fid - 1
			GF[s[1]] = sbase
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4],mem[#mem+5] = 0,0,0,0,types.functy
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = string.byte(string.pack('<i4', fid),1,4)
			if s[3] then
				mem[#mem+1] = 1
			else
				mem[#mem+1] = 0
			end
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = string.byte(string.pack('<i4', sbase+functy.sizeof),1,4)
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = 0,0,0,0
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = 0,0,0,0
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = 0,0,0,0
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = string.byte(string.pack('<i4', s[2]),1,4)
			mem[#mem+1],mem[#mem+2] = 0,0
			assert(base+#mem == sbase+functy.sizeof)
			addString(mem, s[4])
		end
	end
	HEAPBASE = base + #mem
	return base, mem
end

data(memory, addStatics(4, {
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
	'__eq', '__lt', '__le', '__gt', '__ge', '__len', '__tostring',
	'__index', '__newindex', '__mode', '__call', '__unm', '__concat',
	'__add', '__sub', '__mul', '__div', '__idiv', '__mod', '__pow',
	'__bnot', '__band', '__bor', '__bxor', '__bshl', '__bshr',
	'coroutine', 'debug', 'io', 'math', 'os', 'package', 'utf8',
	'select', 'pcall', 'error', 'getmetatable', 'setmetatable', 'type',
	'rawget', 'rawset', 'rawlen', 'rawequal', 'next',
	'create', 'resume', 'yield', 'running', 'status',
	{'select', 1, true, '\x1f\x01\x0c'},
	{'pcall', 1, true, '\x1f\x00\x0c'},
	{'error', 2, false, ''},
	{'coro_create', 1, false, ''},
	{'coro_resume', 1, true, ''},
	{'coro_yield', 0, true, ''},
	{'coro_running', 0, false, ''},
	{'coro_status', 0, false, ''},
	{'debug_getmetatable', 1, false, ''},
	{'debug_setmetatable', 1, false, ''},
	{'math_type', 1, false, ''}
))

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

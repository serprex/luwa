local M = require 'make'
local func, global = M.func, M.global
local importfunc = M.importfunc
local i32, i64, f32, f64 = M.i32, M.i64, M.f32, M.f64

local alloc = require 'alloc'
local types, str, functy, allocsizef = alloc.types, alloc.str, alloc.functy, alloc.allocsizef

NIL = 0
TRUE = 8
FALSE = 16
otmp = M.global(i32, true)
oluastack = M.global(i32, true) -- default to NIL
ostrmt = M.global(i32, true)
markbit = M.global(i32, true)
idcount = M.global(i32, true)

local memory = M.importmemory('', 'm', 1)

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

GN = {
	integer = {},
	float = {},
}
GS = {}
GF = {}

local function doboot()
	return table.unpack(require('bootrt')(
		'./rt/prelude.lua',
		'./rt/astgen.lua', './rt/bcgen.lua',
		'./rt/ast.lua', './rt/bc.lua', './rt/lex.lua'))
end

function getGC(n)
	return GN[math.type(n)][n]
end
local function addHeader(base, mem, ty)
	mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = string.byte(string.pack('<i4', base+#mem), 1, 4)
	mem[#mem+1] = ty
end
local function addString(base, mem, s)
	addHeader(base, mem, types.str)
	mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = string.byte(string.pack('<i4', #s), 1, 4)
	mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = 0,0,0,0
	for j = 1,#s do
		mem[#mem+1] = string.byte(s, j)
	end
	for j = #s+1,allocsizef(str.base + #s)-str.base do
		mem[#mem+1] = 0
	end
end
local function addNumber(base, mem, n)
	local ty = math.type(n)
	assert(ty, 'Non numeric addNumber')
	local lty, bin
	if ty == 'integer' then
		lty, bin = types.int, string.pack('<i8', n)
	else
		lty, bin = types.float, string.pack('<d', n)
	end
	if not GN[ty][bin] then
		GN[ty][bin] = base + #mem
		addHeader(base, mem, lty)
		mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4],
			mem[#mem+5],mem[#mem+6],mem[#mem+7],mem[#mem+8] = string.byte(bin, 1, 8)
		mem[#mem+1],mem[#mem+2],mem[#mem+3] = 0,0,0
	end
	return GN[ty][bin]
end
local function addStatics(base, mem, ...)
	local fid = 0
	for i = 1,select('#', ...) do
		local s, sbase = select(i, ...), base + #mem
		local st = type(s)
		while st == 'function' do
			s = s()
			st = type(s)
		end
		if st == 'string' then
			if not GS[s] then
				GS[s] = sbase
				addString(base, mem, s)
			end
		elseif st == 'number' then
			addNumber(base, mem, s)
		elseif #s == 2 then
			local name, snty = s[1], math.type(s[2])
			assert(snty, '2-pair assumes numeric')
			GN[ty][name] = addNumber(base, mem, s[2])
		else -- { funcname, paramc, isdotdotdot, bc, consts?, localc? }
			fid = fid - 1
			GF[s[1]] = sbase
			addHeader(base, mem, types.functy)
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = string.byte(string.pack('<i4', fid),1,4)
			if s[3] then
				mem[#mem+1] = 1
			else
				mem[#mem+1] = 0
			end
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = string.byte(string.pack('<i4', sbase+functy.sizeof),1,4)
			local vbase = #mem
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = 0,0,0,0
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = 0,0,0,0
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = string.byte(string.pack('<i4', s[6] or 0),1,4)
			mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = string.byte(string.pack('<i4', s[2]),1,4)
			mem[#mem+1],mem[#mem+2] = 0,0
			assert(base+#mem == sbase+functy.sizeof)
			addString(base, mem, s[4])
			local s5 = s[5]
			if s5 then
				mem[vbase+1],mem[vbase+2],mem[vbase+3],mem[vbase+4] = string.byte(string.pack('<i4', base+#mem),1,4)
				addHeader(base, mem, types.vec)
				mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = string.byte(string.pack('<i4', #s5),1,4)
				for i=1, #s5 do
					local s5i = assert(s5[i](), 'Got falsy value from s5')
					mem[#mem+1],mem[#mem+2],mem[#mem+3],mem[#mem+4] = string.byte(string.pack('<i4', s5i),1,4)
				end
				while (base+#mem&7) ~= 0 do
					mem[#mem+1] = 0
				end
			end
		end
	end
	HEAPBASE = base + #mem
	assert((HEAPBASE&7) == 0)
	while mem[#mem] == 0 do
		mem[#mem] = nil
	end
	return base, mem
end

local image = M.data(memory, addStatics(4, {
	-- nil
	2, 0, 0, 0,
	-- false
	8, 0, 0, 0, 3, 0, 0 ,0,
	-- true
	16, 0, 0, 0, 3, 1, 0, 0,
}, 'float', 'integer', 'normal', 'suspended', 'running', 'dead', 'file', 'closed file',
	'nil', 'number', 'string', 'boolean', 'table', 'function', 'thread', 'userdata',
	'b', 't', 'bt', 'n', 'a', 'l', 'L', 'r', 'w', 'r+', 'w+', 'a+',
	'set', 'cur', 'end', 'no', 'full', 'line', 'exit', 'signal',
	'collect', 'stop', 'restart', 'count', 'step', 'setpause', 'setstepmul', 'isrunning',
	'__eq', '__lt', '__le', '__gt', '__ge', '__len',
	'__index', '__newindex', '__mode', '__call', '__unm', '__concat',
	'__add', '__sub', '__mul', '__div', '__idiv', '__mod', '__pow',
	'__bnot', '__band', '__bor', '__bxor', '__bshl', '__bshr',
	'coroutine', 'debug', 'io', 'math', 'os', 'package', 'utf8',
	'select', 'pcall', 'error', 'getmetatable', 'setmetatable', 'type',
	'rawget', 'rawset', 'rawlen', 'rawequal', 'next',
	'create', 'resume', 'yield', 'running', 'status',
	-- begin _luwa fields
	'lexgen', 'astgen', 'bcgen', 'lex', 'ast', 'bc',
	'stdin', 'stdout', 'ioread', 'iowrite', 'ioflush', 'ioclose',
	'iosetvbuf', 'vec_new',
	'fn_set_localc', 'fn_set_paramc', 'fn_set_isdotdotdot',
	'fn_set_bc', 'fn_set_frees', 'fn_set_consts',
	{'pcall', 1, true, '\x1f\x00'},
	{'select', 1, true, '\x1f\x01'},
	{'error', 2, false, '\x1f\x07'},
	{'type', 1, false, '\x1f\x0b\x0c'},
	{'coro_create', 1, false, '\x1f\x08\x0c'},
	{'coro_resume', 1, true, '\x1f\x09'},
	{'coro_yield', 0, true, '\x1f\x0a'},
	{'coro_running', 0, false, '\x1f\x03\x0c'},
	{'coro_status', 0, false, '\x1f\x02\x0c'},
	{'debug_getmetatable', 1, false, '\x1f\x04\x0c'},
	{'debug_setmetatable', 1, false, '\x1f\x05\x0c'},
	{'math_type', 1, false, '\x1f\x06\x0c'},
	{'io_type', 1, false, '\x1f\x1b\x0c'},
	{'_stdin', 0, false, '\x1f\x0c\x0c'},
	{'_stdout', 0, false, '\x1f\x0d\x0c'},
	{'_ioread', 2, false, '\x1f\x0e\x0c'},
	{'_iowrite', 1, true, '\x1f\x0f\x0c'},
	{'_ioflush', 1, false, '\x1f\x10\x0c'},
	{'_ioclose', 1, false, '\x1f\x11\x0c'},
	{'_iosetvbuf', 2, false, '\x1f\x12\x0c'},
	{'_fn_set_localc', 2, false, '\x1f\x13\x0c'},
	{'_fn_set_paramc', 2, false, '\x1f\x14\x0c'},
	{'_fn_set_isdotdotdot', 2, false, '\x1f\x15\x0c'},
	{'_fn_set_bc', 2, false, '\x1f\x16\x0c'},
	{'_fn_set_frees', 2, false, '\x1f\x17\x0c'},
	{'_fn_set_consts', 2, false, '\x1f\x18\x0c'},
	{'_vec_new', 1, false, '\x1f\x19\x0c'},
	{'_lex', 1, false, '\x1f\x1a\x0c'},
	(BOOTRT or doboot)()
))

heaptip = global(i32, true, HEAPBASE)

local igcfix = importfunc('', 'gcfix')
local igcmark = importfunc('', 'gcmark')
local echo = importfunc('', 'echo', i32, i32)
local echoptr = importfunc('', 'echoptr', i32, i32)
local sin = importfunc('', 'sin', f64, f64)
local cos = importfunc('', 'cos', f64, f64)
local tan = importfunc('', 'tan', f64, f64)
local asin = importfunc('', 'asin', f64, f64)
local acos = importfunc('', 'acos', f64, f64)
local atan = importfunc('', 'atan', f64, f64)
local atan2 = importfunc('', 'atan2', f64, f64, f64)
local exp = importfunc('', 'exp', f64, f64)
local log = importfunc('', 'log', f64, f64)

local setluastack = func(i32, void, function(f, x)
	f:load(x)
	f:storeg(oluastack)
end)
local getluastack = func(i32, function(f)
	f:loadg(oluastack)
end)

local echodrop = func(i32, void, function(f, x)
	f:load(x)
	f:call(echo)
	f:drop()
end)

local echodrop2 = func(i32, i32, i32, function(f, x, y)
	f:load(x)
	f:load(y)
	f:call(echodrop)
	f:call(echo)
end)

return {
	memory = memory,
	image = image,
	igcfix = igcfix,
	igcmark = igcmark,
	echo = echo,
	echoptr = echoptr,
	sin = sin,
	cos = cos,
	tan = tan,
	asin = asin,
	acos = acos,
	atan = atan,
	atan2 = atan2,
	exp = exp,
	log = log,
	setluastack = setluastack,
	getluastack = getluastack,
	echodrop = echodrop,
	echodrop2 = echodrop2,
}

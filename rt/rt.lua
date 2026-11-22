local M = require 'make'
local func, global = M.func, M.global
local importfunc = M.importfunc
local i32, i64, f32, f64 = M.i32, M.i64, M.f32, M.f64

local alloc = require 'alloc'
local types, str, functy, allocsizef = alloc.types, alloc.str, alloc.functy, alloc.allocsizef

NIL = 0
FALSE = 8
TRUE = 16
otmp = M.global(i32, true)
oluastack = M.global(i32, true)
ostrmt = M.global(i32, true)
markbit = M.global(i32, true)
idcount = M.global(i32, true)

local memory = M.importmemory('', 'm', 1)

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

-- Builtins below are tiny hand written bytecode, built from bc.lua so opcode numbers stay in sync
local bc = require 'bc'
local function SYS(n) return string.char(bc.Syscall, n) end
local LOADPARAM0 = string.char(bc.LoadParam, 0, 0, 0, 0)
local RET = string.char(bc.Return)

local Version = 'Luwa ' .. io.open('package.json'):read('a'):gmatch('"version": "([%d.]*)"')()

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
	'__bnot', '__band', '__bor', '__bxor', '__shl', '__shr',
	'coroutine', 'debug', 'io', 'math', 'os', 'package', 'utf8',
	'select', 'pcall', 'error', 'getmetatable', 'setmetatable', 'type',
	'rawget', 'rawset', 'rawlen', 'rawequal', 'next',
	'create', 'resume', 'yield', 'running', 'status',
	'abs', 'ceil', 'floor', 'sin', 'cos', 'tan', 'asin', 'acos', 'exp', 'log', 'atan',
	'byte', 'char',
	'_VERSION', Version,
	-- begin _luwa fields
	'lexgen', 'astgen', 'bcgen', 'lex', 'ast', 'bc', 'lpeg',
	'stdin', 'stdout', 'ioread', 'iowrite', 'ioflush', 'ioclose',
	'iosetvbuf', 'vec_new', 'random',
	'fn_new', 'fn_set_localc', 'fn_set_paramc', 'fn_set_isdotdotdot',
	'fn_set_bc', 'fn_set_frees', 'fn_set_consts',
	{'error', 2, false, SYS(0x07)},
	{'next', 2, false, SYS(0x1d) .. RET},
	{'pcall', 1, true, SYS(0x00)},
	{'rawget', 2, false, SYS(0x1b) .. RET},
	{'rawset', 3, false, SYS(0x1c) .. LOADPARAM0 .. RET},
	{'select', 1, true, SYS(0x01) .. RET},
	{'type', 1, false, SYS(0x0b) .. RET},
	{'coro_create', 1, false, SYS(0x08) .. RET},
	{'coro_resume', 1, true, SYS(0x09)},
	{'coro_yield', 0, true, SYS(0x0a)},
	{'coro_running', 0, false, SYS(0x03) .. RET},
	{'coro_status', 0, false, SYS(0x02) .. RET},
	{'debug_getmetatable', 1, false, SYS(0x04) .. RET},
	{'debug_setmetatable', 1, false, SYS(0x05) .. LOADPARAM0 .. RET},
	{'math_type', 1, false, SYS(0x06) .. RET},
	{'math_abs', 1, false, SYS(31) .. RET},
	{'math_ceil', 1, false, SYS(32) .. RET},
	{'math_floor', 1, false, SYS(33) .. RET},
	{'math_sin', 1, false, SYS(34) .. RET},
	{'math_cos', 1, false, SYS(35) .. RET},
	{'math_tan', 1, false, SYS(36) .. RET},
	{'math_asin', 1, false, SYS(37) .. RET},
	{'math_acos', 1, false, SYS(38) .. RET},
	{'math_exp', 1, false, SYS(39) .. RET},
	{'math_log', 2, false, SYS(40) .. RET},
	{'math_atan', 2, false, SYS(41) .. RET},
	{'io_type', 1, false, SYS(0x1b) .. RET},
	{'_stdin', 0, false, SYS(0x0c) .. RET},
	{'_stdout', 0, false, SYS(0x0d) .. RET},
	{'_ioread', 2, false, SYS(0x0e) .. RET},
	{'_iowrite', 1, true, SYS(0x0f) .. RET},
	{'_ioflush', 1, false, SYS(0x10) .. RET},
	{'_ioclose', 1, false, SYS(0x11) .. RET},
	{'_iosetvbuf', 2, false, SYS(0x12) .. RET},
	{'_fn_set_localc', 2, false, SYS(0x13) .. RET},
	{'_fn_set_paramc', 2, false, SYS(0x14) .. RET},
	{'_fn_set_isdotdotdot', 2, false, SYS(0x15) .. RET},
	{'_fn_set_bc', 2, false, SYS(0x16) .. RET},
	{'_fn_set_frees', 2, false, SYS(0x17) .. RET},
	{'_fn_set_consts', 2, false, SYS(0x18) .. RET},
	{'_vec_new', 0, true, SYS(0x19) .. RET},
	{'_fn_new', 0, false, SYS(44) .. RET},
	{'_lex', 1, false, SYS(0x1a) .. RET},
	{'_random', 0, false, SYS(0x1e) .. RET},
	{'string_byte', 3, false, SYS(42) .. RET},
	{'string_char', 0, true, SYS(43) .. RET},
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
local random = importfunc('', 'random', f64)
local exp = importfunc('', 'exp', f64, f64)
local log = importfunc('', 'log', f64, f64)
local pow = importfunc('', 'pow', f64, f64, f64)

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
	random = random,
	exp = exp,
	log = log,
	pow = pow,
	setluastack = setluastack,
	getluastack = getluastack,
	echodrop = echodrop,
	echodrop2 = echodrop2,
	Version = Version,
}

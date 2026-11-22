-- Globals, imports, and the static objects: strings, numbers & functions the runtime and prelude need.
-- Statics are made by initstatics (run by genesis) from passive data, each one goes in its own global.
-- GS[s] / GN.integer[pack] / GN.float[pack] / GF[name] are those globals
local M = require 'make'
local func, global = M.func, M.global
local importfunc = M.importfunc

local alloc = require 'alloc'
local types, R, str, bytes, vals, int, float, functy =
	alloc.types, alloc.R, alloc.str, alloc.bytes, alloc.vals, alloc.int, alloc.float, alloc.functy

-- microbc's Obj atoms
NIL = 'nil'
FALSE = 'false'
TRUE = 'true'

oluastack = M.global(R.coro, true)
ostrmt = M.global(R.tbl, true)

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

-- Static object list, in creation order: { kind, global, data... }
local statics = {}
-- All string & bytecode bytes, a passive data segment
local blob = {}
local function addbytes(s)
	local off = #blob
	for j = 1, #s do
		blob[#blob+1] = s:byte(j)
	end
	return off
end
local function addString(s)
	if not GS[s] then
		local g = global(R.str, true)
		GS[s] = g
		statics[#statics+1] = { 'str', g, addbytes(s), #s }
	end
	return GS[s]
end
local function addNumber(n)
	local ty = math.type(n)
	assert(ty, 'Non numeric addNumber')
	local bin = ty == 'integer' and string.pack('<i8', n) or string.pack('<d', n)
	if not GN[ty][bin] then
		local g = global(ty == 'integer' and R.int or R.float, true)
		GN[ty][bin] = g
		statics[#statics+1] = { ty, g, n }
	end
	return GN[ty][bin]
end
local function addStatics(...)
	for i = 1,select('#', ...) do
		local s = select(i, ...)
		local st = type(s)
		while st == 'function' do
			s = s()
			st = type(s)
		end
		if st == 'string' then
			addString(s)
		elseif st == 'number' then
			addNumber(s)
		else -- { funcname, paramc, isdotdotdot, bc, consts?, localc? }
			local g = global(R.functy, true)
			GF[s[1]] = g
			local consts
			if s[5] then
				consts = {}
				for j = 1, #s[5] do
					consts[j] = assert(s[5][j](), 'Got falsy value from consts')
				end
			end
			statics[#statics+1] = { 'fn', g, s[2], s[3], addbytes(s[4]), #s[4], consts, s[6] or 0 }
		end
	end
end

-- Builtins below are tiny hand written bytecode, built from bc.lua so opcode numbers stay in sync
local bc = require 'bc'
local sysnum = {}
for i, name in ipairs(require 'sys') do
	sysnum[name] = i-1
end
local function SYS(name) return string.char(bc.Syscall, (assert(sysnum[name], name))) end
local LOADPARAM0 = string.char(bc.LoadParam, 0, 0, 0, 0)
local RET = string.char(bc.Return)

local Version = 'Luwa ' .. io.open('package.json'):read('a'):gmatch('"version": "([%d.]*)"')()

addStatics('float', 'integer', 'normal', 'suspended', 'running', 'dead', 'file', 'closed file',
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
	'byte', 'char', 'load',
	'_VERSION', Version,
	-- begin _luwa fields
	'lexgen', 'astgen', 'bcgen', 'lex', 'ast', 'bc', 'lpeg',
	'stdin', 'stdout', 'ioread', 'iowrite', 'ioflush', 'ioclose',
	'iosetvbuf', 'vec_new', 'random',
	'fn_new', 'fn_set_localc', 'fn_set_paramc', 'fn_set_isdotdotdot',
	'fn_set_bc', 'fn_set_frees', 'fn_set_consts',
	{'error', 2, false, SYS'error'},
	{'next', 2, false, SYS'next' .. RET},
	{'pcall', 1, true, SYS'pcall'},
	{'rawget', 2, false, SYS'rawget' .. RET},
	{'rawset', 3, false, SYS'rawset' .. LOADPARAM0 .. RET},
	{'select', 1, true, SYS'select' .. RET},
	{'type', 1, false, SYS'type' .. RET},
	{'coro_create', 1, false, SYS'coro_create' .. RET},
	{'coro_resume', 1, true, SYS'coro_resume'},
	{'coro_yield', 0, true, SYS'coro_yield'},
	{'coro_running', 0, false, SYS'coro_running' .. RET},
	{'coro_status', 0, false, SYS'coro_status' .. RET},
	{'debug_getmetatable', 1, false, SYS'debug_getmetatable' .. RET},
	{'debug_setmetatable', 1, false, SYS'debug_setmetatable' .. LOADPARAM0 .. RET},
	{'math_type', 1, false, SYS'math_type' .. RET},
	{'math_abs', 1, false, SYS'math_abs' .. RET},
	{'math_ceil', 1, false, SYS'math_ceil' .. RET},
	{'math_floor', 1, false, SYS'math_floor' .. RET},
	{'math_sin', 1, false, SYS'math_sin' .. RET},
	{'math_cos', 1, false, SYS'math_cos' .. RET},
	{'math_tan', 1, false, SYS'math_tan' .. RET},
	{'math_asin', 1, false, SYS'math_asin' .. RET},
	{'math_acos', 1, false, SYS'math_acos' .. RET},
	{'math_exp', 1, false, SYS'math_exp' .. RET},
	{'math_log', 2, false, SYS'math_log' .. RET},
	{'math_atan', 2, false, SYS'math_atan' .. RET},
	{'io_type', 1, false, SYS'io_type' .. RET},
	{'_stdin', 0, false, SYS'_stdin' .. RET},
	{'_stdout', 0, false, SYS'_stdout' .. RET},
	{'_ioread', 2, false, SYS'_ioread' .. RET},
	{'_iowrite', 1, true, SYS'_iowrite' .. RET},
	{'_ioflush', 1, false, SYS'_ioflush' .. RET},
	{'_ioclose', 1, false, SYS'_ioclose' .. RET},
	{'_iosetvbuf', 2, false, SYS'_iosetvbuf' .. RET},
	{'_fn_set_localc', 2, false, SYS'_fn_set_localc' .. RET},
	{'_fn_set_paramc', 2, false, SYS'_fn_set_paramc' .. RET},
	{'_fn_set_isdotdotdot', 2, false, SYS'_fn_set_isdotdotdot' .. RET},
	{'_fn_set_bc', 2, false, SYS'_fn_set_bc' .. RET},
	{'_fn_set_frees', 2, false, SYS'_fn_set_frees' .. RET},
	{'_fn_set_consts', 2, false, SYS'_fn_set_consts' .. RET},
	{'_vec_new', 0, true, SYS'_vec_new' .. RET},
	{'_fn_new', 0, false, SYS'_fn_new' .. RET},
	{'_lex', 1, false, SYS'_lex' .. RET},
	{'_random', 0, false, SYS'_random' .. RET},
	{'string_byte', 3, false, SYS'string_byte' .. RET},
	{'string_char', 0, true, SYS'string_char' .. RET},
	(BOOTRT or doboot)())

local blobdata = M.passivedata(blob)

-- Make every static object & put it in its global
local initstatics = func(function(f)
	for idx, s in ipairs(statics) do
		local kind, g = s[1], s[2]
		if kind == 'str' then
			f:i32(types.str)
			f:i32(0)
			f:i32(s[3])
			f:i32(s[4])
			f:arraynewdata(bytes, blobdata)
			f:structnew(str)
		elseif kind == 'integer' then
			f:i32(types.int)
			f:i64(s[3])
			f:structnew(int)
		elseif kind == 'float' then
			f:i32(types.float)
			f:f64(s[3])
			f:structnew(float)
		else
			local paramc, isdotdotdot, off, len, consts, localc = s[3], s[4], s[5], s[6], s[7], s[8]
			f:i32(types.functy)
			-- static functions get ids below 0, so they never clash with nextid's
			f:i32(idx - #statics - 1)
			f:i32(isdotdotdot and 1 or 0)
			f:i32(off)
			f:i32(len)
			f:arraynewdata(bytes, blobdata)
			if consts then
				for j = 1, #consts do
					f:loadg(consts[j])
				end
				f:arraynewfixed(vals, #consts)
			else
				f:refnull(vals)
			end
			f:refnull(vals)
			f:i32(localc)
			f:i32(paramc)
			f:structnew(functy)
		end
		f:storeg(g)
	end
end)

local echo = importfunc('', 'echo', i32, i32)
-- Print any value, for debugging & error messages
local echoobj = importfunc('', 'echoobj', V, void)
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

return {
	initstatics = initstatics,
	echo = echo,
	echoobj = echoobj,
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
	Version = Version,
}

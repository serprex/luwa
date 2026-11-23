-- Object layout on WasmGC. The engine owns objects, so refs held in locals stay valid across allocation.
-- A Lua value is V, a nullable eqref: nil is null, ints from -2^30 to 2^30-1 are i31s,
-- everything else is a struct under $obj. Its first field is a type id, so code can switch on it.
-- Bigger ints are int structs, an int never has both forms. false & true are 2 objs made at start
local M = require 'make'
local func = M.func
local i8 = M.i8

local types = {
	int = 0,
	float = 1,
	single = 2, -- nil, false, true. nil is null, false & true are plain objs
	tbl = 3,
	str = 4,
	vec = 5,
	buf = 6, -- unused, buffers aren't Lua values now
	functy = 7,
	coro = 8,
}
local corostate = {
	dead = 0,
	norm = 1,
	live = 2,
	wait = 3,
}

V = M.eqref

local bytes = M.array(M.mut(i8), { name = 'bytes' })
local vals = M.array(M.mut(V), { name = 'vals' })
local i32s = M.array(M.mut(i32), { name = 'i32s' })

local obj = M.struct({ { i8, name = 'type' } }, { name = 'obj', final = false })
local int = M.struct({ { i8, name = 'type' }, { i64, name = 'val' } }, { name = 'int', super = obj })
local float = M.struct({ { i8, name = 'type' }, { f64, name = 'val' } }, { name = 'float', super = obj })
-- hash & id are 0 until worked out. id is only for %p on long strings
local str = M.struct({
	{ i8, name = 'type' },
	{ i32, mut = true, name = 'hash' },
	{ M.ref(bytes), name = 'bytes' },
	{ i32, mut = true, name = 'id' },
}, { name = 'str', super = obj })
-- Fixed size list of values. Lua code sees it from the lexer & _luwa.vec_new
local vec = M.struct({
	{ i8, name = 'type' },
	{ M.ref(vals), name = 'arr' },
}, { name = 'vec', super = obj })
-- Objects hashed by identity get an id, wasm has no addresses
local idobj = M.struct({ { i8, name = 'type' }, { i32, name = 'id' } }, { name = 'idobj', super = obj, final = false })
-- Hash only for now: hash holds key, value pairs. hlen counts used pairs
local tbl = M.struct(nil, { name = 'tbl', super = idobj })
tbl:define{
	{ i8, name = 'type' },
	{ i32, name = 'id' },
	{ i32, mut = true, name = 'len' },
	{ i32, mut = true, name = 'hlen' },
	{ M.ref(vals), mut = true, name = 'hash' },
	{ M.refnull(tbl), mut = true, name = 'meta' },
}
local functy = M.struct({
	{ i8, name = 'type' },
	{ i32, name = 'id' },
	{ i8, mut = true, name = 'isdotdotdot' },
	{ M.refnull(bytes), mut = true, name = 'bc' },
	{ M.refnull(vals), mut = true, name = 'consts' },
	{ M.refnull(vals), mut = true, name = 'frees' },
	{ i32, mut = true, name = 'localc' },
	{ i32, mut = true, name = 'paramc' },
	-- Lua table from load: source, name, line table & such, for errors & debug. nil for builtins
	{ V, mut = true, name = 'info' },
}, { name = 'functy', super = idobj })
-- Growable lists: the Lua value stack, and the call frames (8 i32s each, see frame.lua)
local stack = M.struct({
	{ i32, mut = true, name = 'len' },
	{ M.ref(vals), mut = true, name = 'arr' },
}, { name = 'stack' })
local frames = M.struct({
	{ i32, mut = true, name = 'len' },
	{ M.ref(i32s), mut = true, name = 'arr' },
}, { name = 'frames' })
local coro = M.struct(nil, { name = 'coro', super = idobj })
coro:define{
	{ i8, name = 'type' },
	{ i32, name = 'id' },
	{ i8, mut = true, name = 'state' },
	{ M.refnull(coro), mut = true, name = 'caller' },
	{ M.refnull(stack), mut = true, name = 'stack' },
	{ M.refnull(frames), mut = true, name = 'data' },
}
-- Captured variable, stored in a local's slot. Not a Lua value
-- id is 0 until debug.upvalueid asks for one
local box = M.struct({ { V, mut = true, name = 'val' }, { i32, mut = true, name = 'id' } }, { name = 'box' })

-- Nullable ref of each type, what locals & fields use
local R = {
	bytes = M.refnull(bytes),
	vals = M.refnull(vals),
	i32s = M.refnull(i32s),
	obj = M.refnull(obj),
	int = M.refnull(int),
	float = M.refnull(float),
	str = M.refnull(str),
	vec = M.refnull(vec),
	idobj = M.refnull(idobj),
	tbl = M.refnull(tbl),
	functy = M.refnull(functy),
	stack = M.refnull(stack),
	frames = M.refnull(frames),
	coro = M.refnull(coro),
	box = M.refnull(box),
}

-- false & true, made once
local function newsingle(f)
	f:i32(types.single)
	f:structnew(obj)
end
gfalse = M.global(M.ref(obj), false, newsingle)
gtrue = M.global(M.ref(obj), false, newsingle)

-- Constant values, emitted inline
local function lnil(f)
	f:refnull(M.heap.eq)
end
local function lfalse(f)
	f:loadg(gfalse)
end
local function ltrue(f)
	f:loadg(gtrue)
end
-- i32 flag on the stack to false or true
local function lbool(f)
	f:iff(M.ref(obj), function()
		f:loadg(gtrue)
	end, function()
		f:loadg(gfalse)
	end)
end

idcount = M.global(i32, true)

-- idcount += 1, return it
local nextid = func(i32, function(f)
	f:loadg(idcount)
	f:i32(1)
	f:add()
	f:storeg(idcount)
	f:loadg(idcount)
end)

-- Type id of the value on the stack: an obj's type field, int for i31s, single for nil
local function typeofst(f)
	f:block(M.functype({ V }, i32), function(out)
		f:block(M.functype({ V }, M.ref(obj)), function(isobj)
			f:block(M.functype({ V }, M.ref(M.heap.i31)), function(isi31)
				f:broncast(isi31, V, M.ref(M.heap.i31))
				f:broncast(isobj, V, M.ref(obj))
				f:drop()
				f:i32(types.single)
				f:br(out)
			end)
			f:drop()
			f:i32(types.int)
			f:br(out)
		end)
		f:structget(obj, 'type', false)
	end)
end
-- Type id of any value
local typeof = func(V, i32, function(f, o)
	f:load(o)
	typeofst(f)
end)

-- i64 of the int on the stack, an i31 or an int struct
local function intvalst(f)
	f:block(M.functype({ V }, i64), function(out)
		f:block(M.functype({ V }, M.ref(M.heap.i31)), function(isi31)
			f:broncast(isi31, V, M.ref(M.heap.i31))
			f:refcast(M.ref(int))
			f:structget(int, 'val')
			f:br(out)
		end)
		f:i31gets()
		f:i64extends()
	end)
end
local function intval(f, o)
	f:load(o)
	intvalst(f)
end

-- Is i64 x in i31 range? x + 2^30 < 2^31 unsigned
local function fitsi31(f, x)
	f:load(x)
	f:i64(0x40000000)
	f:add()
	f:i64(0x80000000)
	f:ltu()
end
-- Int struct for x, only for x outside i31 range
local boxi64 = func(i64, M.ref(int), function(f, x)
	f:i32(types.int)
	f:load(x)
	f:structnew(int)
end)
-- Int value of x: an i31 when it fits
local newi64 = func(i64, V, function(f, x)
	fitsi31(f, x)
	f:iff(V, function()
		f:load(x)
		f:i32wrap()
		f:refi31()
	end, function()
		f:load(x)
		f:call(boxi64)
	end)
end)

local newf64 = func(f64, M.ref(float), function(f, x)
	f:i32(types.float)
	f:load(x)
	f:structnew(float)
end)

-- String of sz zero bytes
local newstr = func(i32, M.ref(str), function(f, sz)
	f:i32(types.str)
	f:i32(0)
	f:load(sz)
	f:arraynewdefault(bytes)
	f:i32(0)
	f:structnew(str)
end)
local strfrombytes = func(M.refnull(bytes), M.ref(str), function(f, b)
	f:i32(types.str)
	f:i32(0)
	f:load(b)
	f:refasnonnull()
	f:i32(0)
	f:structnew(str)
end)

local newtbl = func(M.ref(tbl), function(f)
	f:i32(types.tbl)
	f:call(nextid)
	f:i32(0)
	f:i32(0)
	-- 4 pairs
	f:i32(8)
	f:arraynewdefault(vals)
	f:refnull(tbl)
	f:structnew(tbl)
end)

local newfunc = func(M.ref(functy), function(f)
	f:i32(types.functy)
	f:call(nextid)
	f:i32(0)
	f:refnull(bytes)
	f:refnull(vals)
	f:refnull(vals)
	f:i32(0)
	f:i32(0)
	f:refnull(M.heap.eq)
	f:structnew(functy)
end)

local newstack = func(i32, M.ref(stack), function(f, sz)
	f:i32(0)
	f:load(sz)
	f:arraynewdefault(vals)
	f:structnew(stack)
end)
local newframes = func(i32, M.ref(frames), function(f, sz)
	f:i32(0)
	f:load(sz)
	f:arraynewdefault(i32s)
	f:structnew(frames)
end)

local newcoro = func(M.ref(coro), function(f)
	f:i32(types.coro)
	f:call(nextid)
	f:i32(corostate.wait)
	f:refnull(coro)
	f:refnull(stack)
	f:refnull(frames)
	f:structnew(coro)
end)

local newbox = func(V, M.ref(box), function(f, v)
	f:load(v)
	f:i32(0)
	f:structnew(box)
end)

return {
	types = types,
	corostate = corostate,
	bytes = bytes,
	vals = vals,
	i32s = i32s,
	obj = obj,
	int = int,
	float = float,
	str = str,
	vec = vec,
	idobj = idobj,
	tbl = tbl,
	functy = functy,
	stack = stack,
	frames = frames,
	coro = coro,
	box = box,
	R = R,
	lnil = lnil,
	lfalse = lfalse,
	ltrue = ltrue,
	lbool = lbool,
	nextid = nextid,
	typeof = typeof,
	typeofst = typeofst,
	intval = intval,
	intvalst = intvalst,
	fitsi31 = fitsi31,
	boxi64 = boxi64,
	newi64 = newi64,
	newf64 = newf64,
	newstr = newstr,
	strfrombytes = strfrombytes,
	newtbl = newtbl,
	newfunc = newfunc,
	newstack = newstack,
	newframes = newframes,
	newcoro = newcoro,
	newbox = newbox,
}

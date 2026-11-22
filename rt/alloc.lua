-- Object layout on WasmGC. The engine owns objects, so refs held in locals stay valid across allocation.
-- A Lua value is V, a nullable eqref: nil is null, false/true are i31 0/1,
-- everything else is a struct under $obj. Its first field is a type id, so code can switch on it
local M = require 'make'
local func = M.func
local i8 = M.i8

local types = {
	int = 0,
	float = 1,
	single = 2, -- nil, false, true. Not a struct, typeof gives this
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
-- hash is 0 until worked out
local str = M.struct({
	{ i8, name = 'type' },
	{ i32, mut = true, name = 'hash' },
	{ M.ref(bytes), name = 'bytes' },
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
local box = M.struct({ { V, mut = true, name = 'val' } }, { name = 'box' })

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

-- Constant values, emitted inline
local function lnil(f)
	f:refnull(M.heap.eq)
end
local function lfalse(f)
	f:i32(0)
	f:refi31()
end
local function ltrue(f)
	f:i32(1)
	f:refi31()
end
-- i32 0 or 1 on the stack to false or true
local function lbool(f)
	f:refi31()
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

-- Type id of any value
local typeof = func(V, i32, function(f, o)
	f:block(M.ref(obj), function(isobj)
		f:load(o)
		f:broncast(isobj, V, M.ref(obj))
		f:drop()
		f:i32(types.single)
		f:ret()
	end)
	f:structget(obj, 'type', false)
end)

local newi64 = func(i64, M.ref(int), function(f, x)
	f:i32(types.int)
	f:load(x)
	f:structnew(int)
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
	f:structnew(str)
end)
local strfrombytes = func(M.refnull(bytes), M.ref(str), function(f, b)
	f:i32(types.str)
	f:i32(0)
	f:load(b)
	f:refasnonnull()
	f:structnew(str)
end)

-- vec of sz nils
local newvec = func(i32, M.ref(vec), function(f, sz)
	f:i32(types.vec)
	f:load(sz)
	f:arraynewdefault(vals)
	f:structnew(vec)
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
	newi64 = newi64,
	newf64 = newf64,
	newstr = newstr,
	strfrombytes = strfrombytes,
	newvec = newvec,
	newtbl = newtbl,
	newfunc = newfunc,
	newstack = newstack,
	newframes = newframes,
	newcoro = newcoro,
	newbox = newbox,
}

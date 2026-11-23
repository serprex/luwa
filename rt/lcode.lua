-- Codegen for lparse.lua, like lcode.c: the state of each function being compiled, bytecode,
-- constants, names & what an expression has made so far. Ops & their order follow what
-- bcgen.lua did, so both make the same bytecode
local M = require 'make'
local func = M.func
local LV = M.eqref

local alloc = require 'alloc'
local _lex = require '_lex'
local _table = require '_table'
local bc = require 'bc'
local R, str, bytes, vals, i32s, stack = alloc.R, alloc.str, alloc.bytes, alloc.vals, alloc.i32s, alloc.stack
local tblget, tblset = _table.tblget, _table.tblset
local bbuf, Rbbuf, newbbuf, bbpush = _lex.bbuf, M.refnull(_lex.bbuf), _lex.newbbuf, _lex.bbpush
local Rvl = R.stack

local C = {}

-- Constant strings, each made the first time it's used from its own passive data
local strfns = {}
function C.S(s)
	local fn = strfns[s]
	if not fn then
		local g = M.global(R.str, true)
		local d = M.passivedata({ s:byte(1, -1) })
		fn = func(M.ref(str), function(f)
			f:block(M.ref(str), function(ok)
				f:loadg(g)
				f:bronnonnull(ok)
				f:i32(0)
				f:i32(#s)
				f:arraynewdata(bytes, d)
				f:call(alloc.strfrombytes)
				f:storeg(g)
				f:loadg(g)
				f:refasnonnull()
			end)
		end)
		fn.name = 'S.' .. s
		strfns[s] = fn
	end
	return fn
end
local S = C.S

-- Growable lists: ilist of i32s, & alloc's stack struct for values
local ilist = M.struct({
	{ i32, mut = true, name = 'len' },
	{ M.ref(i32s), mut = true, name = 'arr' },
}, { name = 'ilist' })
local Ril = M.refnull(ilist)
C.ilist, C.Ril = ilist, Ril
C.newil = func(M.ref(ilist), function(f)
	f:i32(0)
	f:i32(8)
	f:arraynewdefault(i32s)
	f:structnew(ilist)
end)
C.ilpush = func(Ril, i32, void, function(f, l, x)
	local arr, narr = f:locals(R.i32s, 2)
	local len = f:locals(i32)
	f:load(l)
	f:structget(ilist, 'len')
	f:tee(len)
	f:load(l)
	f:structget(ilist, 'arr')
	f:tee(arr)
	f:arraylen()
	f:eq()
	f:iff(function()
		f:load(len)
		f:i32(1)
		f:shl()
		f:arraynewdefault(i32s)
		f:tee(narr)
		f:i32(0)
		f:load(arr)
		f:i32(0)
		f:load(len)
		f:arraycopy(i32s, i32s)
		f:load(l)
		f:load(narr)
		f:refasnonnull()
		f:structset(ilist, 'arr')
		f:load(narr)
		f:store(arr)
	end)
	f:load(arr)
	f:load(len)
	f:load(x)
	f:arrayset(i32s)
	f:load(l)
	f:load(len)
	f:i32(1)
	f:add()
	f:structset(ilist, 'len')
end)
-- l[i], l & i pushed by the caller
function C.ilget(f)
	local i = f:locals(i32)
	f:store(i)
	f:structget(ilist, 'arr')
	f:load(i)
	f:arrayget(i32s)
end
C.newvl = func(M.ref(stack), function(f)
	f:i32(8)
	f:call(alloc.newstack)
end)
C.vlpush = func(Rvl, LV, void, function(f, l, x)
	local arr, narr = f:locals(R.vals, 2)
	local len = f:locals(i32)
	f:load(l)
	f:structget(stack, 'len')
	f:tee(len)
	f:load(l)
	f:structget(stack, 'arr')
	f:tee(arr)
	f:arraylen()
	f:eq()
	f:iff(function()
		f:load(len)
		f:i32(1)
		f:shl()
		f:i32(8)
		f:add()
		f:arraynewdefault(vals)
		f:tee(narr)
		f:i32(0)
		f:load(arr)
		f:i32(0)
		f:load(len)
		f:arraycopy(vals, vals)
		f:load(l)
		f:load(narr)
		f:refasnonnull()
		f:structset(stack, 'arr')
		f:load(narr)
		f:store(arr)
	end)
	f:load(arr)
	f:load(len)
	f:load(x)
	f:arrayset(vals)
	f:load(l)
	f:load(len)
	f:i32(1)
	f:add()
	f:structset(stack, 'len')
end)
-- l[i], l & i pushed by the caller
function C.vlget(f)
	local i = f:locals(i32)
	f:store(i)
	f:structget(stack, 'arr')
	f:load(i)
	f:arrayget(vals)
end
function C.vllen(f)
	f:structget(stack, 'len')
end

-- i32 on the stack as a Lua int, for values that fit an i31
function C.int(f)
	f:refi31()
end
-- Lua int on the stack to i32
function C.toi32(f)
	f:refcast(M.ref(M.heap.i31))
	f:i31gets()
end
-- t[k] = v, each a pusher
function C.tset(f, t, k, v)
	t(f)
	k(f)
	v(f)
	f:call(tblset)
end
-- t[n] = v for an int n
function C.tseti(f, t, n, v)
	t(f)
	if type(n) == 'number' then
		f:i32(n)
	else
		n(f)
	end
	f:refi31()
	v(f)
	f:call(tblset)
end
function C.tsets(f, t, s, v)
	t(f)
	f:call(S(s))
	v(f)
	f:call(tblset)
end

-- A declared name: a local or param of fs, a global declaration, or the strict marker
-- global x leaves for names not declared. prev is what it hides
local K = { loc = 0, param = 1, global = 2, strict = 3 }
C.K = K
local var = M.struct(nil, { name = 'var' })
local Rvar = M.refnull(var)
C.var, C.Rvar = var, Rvar

-- break scope of a loop: the <close> count at its start & where its breaks' jumps are
local brk = M.struct(nil, { name = 'brk' })
brk:define{
	{ M.refnull(brk), name = 'prev' },
	{ i32, name = 'tbcn' },
	{ Ril, name = 'pcs' },
}
C.brk = brk

-- Function being compiled, like lparser.c's FuncState
local fs = M.struct(nil, { name = 'fs' })
local Rfs = M.refnull(fs)
C.fs, C.Rfs = fs, Rfs
local fsfields = {
	{ 'prev', Rfs },
	{ 'bc', Rbbuf },
	{ 'consts', Rvl },
	-- constant -> index. Floats have their own table so 1 & 1.0 stay apart
	{ 'kmap', R.tbl },
	{ 'kfmap', R.tbl },
	{ 'nparams', i32 },
	{ 'isvararg', i32 },
	-- local slots, temps included
	{ 'nlocals', i32 },
	-- vars of outer functions this one uses, in index order
	{ 'frees', Rvl },
	-- pc, line pairs, added when the line changes
	{ 'lineinfo', Ril },
	{ 'lastline', i32 },
	-- pc after an op that can fail -> what made its operands, for error messages
	{ 'opnames', R.tbl },
	-- where the last 2 ops start, for the peepholes in emitop
	{ 'lastop', i32 },
	{ 'prevop', i32 },
	-- values given to ops, any may be a jump target: a byte per value
	{ 'targets', R.bytes },
	-- <close> variables in scope
	{ 'tbcn', i32 },
	{ 'brk', M.refnull(brk) },
	-- locals in scope while emitting & all of them, as lvar, for debug.getlocal
	{ 'actives', Rvl },
	{ 'locvars', Rvl },
	-- ...t: the vararg table's var
	{ 'vargvar', LV },
	{ 'fname', LV },
	{ 'linedef', i32 },
	{ 'lastlinedef', i32 },
	-- where it starts in the source, the key of the first pass's notes on it
	{ 'key', i32 },
	-- vars declared, in order. The first pass looks for captured ones in it
	{ 'decls', Rvl },
	-- gotos to patch at the end, with their labels
	{ 'gotos', Rvl },
	{ 'proto', LV },
	{ 'main', i32 },
}
for i, fd in ipairs(fsfields) do
	fsfields[i] = { fd[2], mut = true, name = fd[1] }
end
fs:define(fsfields)

var:define{
	{ R.str, name = 'name' },
	{ Rfs, name = 'fs' },
	{ i32, name = 'kind' },
	-- param index, or local slot once it has one (-1 till then)
	{ i32, mut = true, name = 'idx' },
	-- 0, or 1 const, 2 close
	{ i32, name = 'attrib' },
	-- a function other than its own uses it, so it lives in a box
	{ i32, mut = true, name = 'captured' },
	{ i32, name = 'key' },
	{ Rvar, mut = true, name = 'prev' },
}

-- A local's debug range
local lvar = M.struct({
	{ Rvar, name = 'var' },
	{ i32, name = 'startpc' },
	{ i32, mut = true, name = 'endpc' },
}, { name = 'lvar' })
C.lvar = lvar

-- Compiler state. pass 1 reads the source for what pass 2 needs to know early: which locals get
-- captured, & where the parts of statements bcgen emitted out of order are
local G = {}
C.G = G
G.pass = M.global(i32, true)
G.cfs = M.global(Rfs, true)
G.curline = M.global(i32, true)
-- what made the value on top of the stack, for error messages, like bcgen's self.desc
G.desc = M.global(LV, true)
-- name -> newest var, & every var in scope in declaration order
G.names = M.global(R.tbl, true)
G.scopevars = M.global(Rvl, true)
-- first pass notes: var key -> captured (& in pass 2 its slot), function key -> its captured locals' keys,
-- statement key -> where its targets & exps are, table key -> where its fields are
G.capt = M.global(R.tbl, true)
G.fcapt = M.global(R.tbl, true)
G.asgn = M.global(R.tbl, true)
G.tabs = M.global(R.tbl, true)
-- load gives tail calls & generic for closing, the prelude's build doesn't. Helpers are prelude
-- functions put in consts, nil without them
G.tailcalls = M.global(i32, true)
G.noinfo = M.global(i32, true)
G.htbcpush = M.global(LV, true)
G.htbcclose = M.global(LV, true)
G.hvargunpack = M.global(LV, true)
G.source = M.global(LV, true)
G.short = M.global(LV, true)

local function fget(f, name)
	f:loadg(G.cfs)
	f:structget(fs, name)
end
C.fget = fget
local function fset(f, name, v)
	f:loadg(G.cfs)
	v(f)
	f:structset(fs, name)
end
C.fset = fset
local function ifpass2(f, body)
	f:loadg(G.pass)
	f:i32(2)
	f:eq()
	f:iff(body)
end
C.ifpass2 = ifpass2

-- Bytecode

-- length of the bytecode, the pc of the next op
local function pc(f)
	fget(f, 'bc')
	f:structget(bbuf, 'len')
end
C.pc = pc
local bcat = func(i32, i32, function(f, i)
	fget(f, 'bc')
	f:structget(bbuf, 'arr')
	f:load(i)
	f:arrayget(bytes, false)
end)
local bcput = func(i32, i32, void, function(f, i, b)
	fget(f, 'bc')
	f:structget(bbuf, 'arr')
	f:load(i)
	f:load(b)
	f:arrayset(bytes)
end)
C.bcat, C.bcput = bcat, bcput

-- x was given to an op, so code may jump to pc x. Values past 0xfffe are never pcs here
local mark = func(i32, void, function(f, x)
	local t, nt = f:locals(R.bytes, 2)
	local n = f:locals(i32)
	f:load(x)
	f:i32(0xffff)
	f:geu()
	f:iff(function()
		f:ret()
	end)
	fget(f, 'targets')
	f:tee(t)
	f:arraylen()
	f:load(x)
	f:leu()
	f:iff(function()
		f:load(t)
		f:arraylen()
		f:i32(1)
		f:shl()
		f:tee(n)
		f:load(x)
		f:i32(64)
		f:add()
		f:load(n)
		f:load(x)
		f:i32(64)
		f:add()
		f:gtu()
		f:select()
		f:arraynewdefault(bytes)
		f:tee(nt)
		f:i32(0)
		f:load(t)
		f:i32(0)
		f:load(t)
		f:arraylen()
		f:arraycopy(bytes, bytes)
		fset(f, 'targets', function() f:load(nt) end)
		f:load(nt)
		f:store(t)
	end)
	f:load(t)
	f:load(x)
	f:i32(1)
	f:arrayset(bytes)
end)
local ismarked = func(i32, i32, function(f, x)
	local t = f:locals(R.bytes)
	fget(f, 'targets')
	f:tee(t)
	f:arraylen()
	f:load(x)
	f:gtu()
	f:iff(i32, function()
		f:load(t)
		f:load(x)
		f:arrayget(bytes, false)
	end, function()
		f:i32(0)
	end)
end)

-- Compare op -> the compare & jump fused op, when a Jif or JifNot follows it
local fusejif = {
	[bc.CmpLt] = bc.JifLt, [bc.CmpLe] = bc.JifLe, [bc.CmpGt] = bc.JifGt, [bc.CmpGe] = bc.JifGe, [bc.CmpEq] = bc.JifEq,
}
local fusejifnot = {
	[bc.CmpLt] = bc.JifNotLt, [bc.CmpLe] = bc.JifNotLe, [bc.CmpGt] = bc.JifNotGt, [bc.CmpGe] = bc.JifNotGe,
	[bc.CmpEq] = bc.JifNotEq,
}
-- Add op. Not then JifNot is Jif. A compare then a jump turns the compare into a fused op, the jump
-- stays for when a metamethod's result comes back. Not when code jumps to the jump
local emitop = func(i32, void, function(f, op)
	local last, len, b = f:locals(i32, 3)
	f:block(function(done)
		f:loop(function(retry)
			fget(f, 'lastop')
			f:store(last)
			pc(f)
			f:store(len)
			f:load(op)
			f:i32(bc.Jif)
			f:eq()
			f:load(op)
			f:i32(bc.JifNot)
			f:eq()
			f:bor()
			f:load(last)
			f:i32(1)
			f:add()
			f:load(len)
			f:eq()
			f:band()
			f:eqz()
			f:brif(done)
			f:load(len)
			f:call(ismarked)
			f:brif(done)
			f:load(last)
			f:call(bcat)
			f:store(b)
			f:load(op)
			f:i32(bc.JifNot)
			f:eq()
			f:load(b)
			f:i32(bc.Not)
			f:eq()
			f:band()
			f:iff(function()
				f:load(last)
				f:call(ismarked)
				f:eqz()
				f:iff(function()
					fget(f, 'bc')
					f:load(last)
					f:structset(bbuf, 'len')
					fset(f, 'lastop', function() fget(f, 'prevop') end)
					f:i32(bc.Jif)
					f:store(op)
					f:br(retry)
				end)
			end)
			local function fuse(map)
				local fs = {}
				for from in pairs(map) do
					fs[#fs+1] = from
				end
				table.sort(fs)
				for _, from in ipairs(fs) do
					local to = map[from]
					f:load(b)
					f:i32(from)
					f:eq()
					f:iff(function()
						f:load(last)
						f:i32(to)
						f:call(bcput)
						f:br(done)
					end)
				end
			end
			f:load(op)
			f:i32(bc.Jif)
			f:eq()
			f:iff(function()
				fuse(fusejif)
			end, function()
				fuse(fusejifnot)
			end)
		end)
	end)
	fset(f, 'prevop', function() fget(f, 'lastop') end)
	fset(f, 'lastop', pc)
	f:loadg(G.curline)
	f:iff(function()
		f:loadg(G.curline)
		fget(f, 'lastline')
		f:ne()
		f:iff(function()
			fset(f, 'lastline', function() f:loadg(G.curline) end)
			fget(f, 'lineinfo')
			pc(f)
			f:call(C.ilpush)
			fget(f, 'lineinfo')
			f:loadg(G.curline)
			f:call(C.ilpush)
		end)
	end)
	fget(f, 'bc')
	f:load(op)
	f:call(bbpush)
end)
emitop.name = 'lcode.emitop'
local emitarg = func(i32, void, function(f, x)
	f:load(x)
	f:call(mark)
	for sh = 0, 24, 8 do
		fget(f, 'bc')
		f:load(x)
		if sh > 0 then
			f:i32(sh)
			f:shru()
		end
		f:call(bbpush)
	end
end)
-- The 4 bytes at i become x
local patch = func(i32, i32, void, function(f, i, x)
	f:load(x)
	f:call(mark)
	for k = 0, 3 do
		f:load(i)
		if k > 0 then
			f:i32(k)
			f:add()
		end
		f:load(x)
		if k > 0 then
			f:i32(k * 8)
			f:shru()
		end
		f:call(bcput)
	end
end)
C.emitop, C.emitarg, C.patch = emitop, emitarg, patch
-- The 4 bytes at i become x, not marked as a target: for lists of jumps kept in their args till patched
C.setarg = func(i32, i32, void, function(f, i, x)
	for k = 0, 3 do
		f:load(i)
		if k > 0 then
			f:i32(k)
			f:add()
		end
		f:load(x)
		if k > 0 then
			f:i32(k * 8)
			f:shru()
		end
		f:call(bcput)
	end
end)

-- the 4 bytes at i, read back
local readarg = func(i32, i32, function(f, i)
	for k = 0, 3 do
		f:load(i)
		if k > 0 then
			f:i32(k)
			f:add()
		end
		f:call(bcat)
		if k > 0 then
			f:i32(k * 8)
			f:shl()
			f:bor()
		end
	end
end)
C.readarg = readarg

-- op(f, opcode, args...): args are numbers or pushers. Gives nothing
local function op(f, opcode, ...)
	f:i32(assert(opcode))
	f:call(emitop)
	for i = 1, select('#', ...) do
		local a = select(i, ...)
		if type(a) == 'number' then
			f:i32(a)
		else
			a(f)
		end
		f:call(emitarg)
	end
end
C.op = op
-- A jump with its target to patch later: pushes where its arg is
local function jump(f, opcode)
	f:i32(opcode)
	f:call(emitop)
	pc(f)
	f:i32(0)
	f:call(emitarg)
end
C.jump = jump

-- opnames[pc] = descs, a list of what made the operands
local function opname(f, descs)
	ifpass2(f, function()
		fget(f, 'opnames')
		pc(f)
		f:refi31()
		descs(f)
		f:call(tblset)
	end)
end
C.opname = opname
-- nil desc to false
local function orfalse(f)
	local d = f:locals(LV)
	f:tee(d)
	f:refisnull()
	f:iff(LV, function()
		alloc.lfalse(f)
	end, function()
		f:load(d)
	end)
end
C.orfalse = orfalse
-- { a, b... }, each a pusher of a value or nil (as false). call adds call = true
local function list(f, items, call)
	local t = f:locals(R.tbl)
	f:call(alloc.newtbl)
	f:store(t)
	for i, it in ipairs(items) do
		f:load(t)
		f:i32(i)
		f:refi31()
		it(f)
		orfalse(f)
		f:call(tblset)
	end
	if call then
		f:load(t)
		f:call(S'call')
		alloc.ltrue(f)
		f:call(tblset)
	end
	f:load(t)
end
C.list = list

-- Constants

-- Index of v in consts, adding it if it's new
local konst = func(LV, i32, function(f, v)
	local map = f:locals(R.tbl)
	local idx = f:locals(LV)
	local n = f:locals(i32)
	f:load(v)
	f:call(alloc.typeof)
	f:i32(alloc.types.float)
	f:eq()
	f:iff(R.tbl, function()
		fget(f, 'kfmap')
	end, function()
		fget(f, 'kmap')
	end)
	f:tee(map)
	f:load(v)
	f:call(tblget)
	f:tee(idx)
	f:refisnull()
	f:iff(i32, function()
		fget(f, 'consts')
		C.vllen(f)
		f:store(n)
		fget(f, 'consts')
		f:load(v)
		f:call(C.vlpush)
		f:load(map)
		f:load(v)
		f:load(n)
		f:refi31()
		f:call(tblset)
		f:load(n)
	end, function()
		f:load(idx)
		C.toi32(f)
	end)
end)
konst.name = 'lcode.konst'
C.konst = konst
-- a new const, for functions
local konstnew = func(LV, i32, function(f, v)
	fget(f, 'consts')
	C.vllen(f)
	fget(f, 'consts')
	f:load(v)
	f:call(C.vlpush)
end)
C.konstnew = konstnew
-- LoadConst of the value v pushes
local function loadk(f, v)
	op(f, bc.LoadConst, function()
		v(f)
		f:call(konst)
	end)
end
C.loadk = loadk
-- LoadConst of an int
local function loadki(f, n)
	loadk(f, function()
		if type(n) == 'number' then
			f:i32(n)
		else
			n(f)
		end
		f:refi31()
	end)
end
C.loadki = loadki

-- "local 'x'" & such: prefix .. name .. "'"
local mkdesc = func(M.ref(str), R.str, M.ref(str), function(f, pre, name)
	local b = f:locals(R.bytes)
	local pl, nl = f:locals(i32, 2)
	f:load(pre)
	f:structget(str, 'bytes')
	f:arraylen()
	f:tee(pl)
	f:load(name)
	f:structget(str, 'bytes')
	f:arraylen()
	f:tee(nl)
	f:add()
	f:i32(1)
	f:add()
	f:arraynewdefault(bytes)
	f:tee(b)
	f:i32(0)
	f:load(pre)
	f:structget(str, 'bytes')
	f:i32(0)
	f:load(pl)
	f:arraycopy(bytes, bytes)
	f:load(b)
	f:load(pl)
	f:load(name)
	f:structget(str, 'bytes')
	f:i32(0)
	f:load(nl)
	f:arraycopy(bytes, bytes)
	f:load(b)
	f:load(pl)
	f:load(nl)
	f:add()
	f:i32(39)
	f:arrayset(bytes)
	f:load(b)
	f:call(alloc.strfrombytes)
end)
C.mkdesc = mkdesc

-- Errors, see lparse.lua. raise is set there
C.E = {
	expected = 1, -- 'x' expected near
	unexpected = 2, -- unexpected symbol near
	close = 3, -- 'x' expected (to close 'y' at line n) near
	lex = 4, -- lexing error: n is its code, s & e from the lexer
	syntax = 5, -- syntax error near
	const = 10, -- attempt to assign to const variable 'arg'
	undeclared = 11, -- variable 'arg' not declared
	envglobal = 12, -- _ENV is global when accessing variable 'arg'
	attrib = 13, -- unknown attribute 'arg'
	multitbc = 14, -- multiple to-be-closed variables in local list
	globaltbc = 15, -- global variables cannot be to-be-closed
	label = 16, -- label 'arg' already defined
	breakout = 17, -- break outside of loop
	nolabel = 18, -- no visible label 'arg' for goto
	intoscope = 19, -- <goto arg> at line n jumps into the scope of 'arg2'
	varg = 20, -- '...' outside of a vararg function
}
C.errs = {}
for _, n in ipairs{ 'code', 'line', 's', 'e', 'tok', 'n', 'n2' } do
	C.errs[n] = M.global(i32, true)
end
C.errs.arg = M.global(LV, true)
C.errs.arg2 = M.global(LV, true)
C.errtag = M.tag(M.functype({}, {}))
-- A compile error at line with name arg, not about the token. arg & n are pushers or nil
local semerr = func(i32, i32, LV, i32, void, function(f, code, line, arg, n)
	f:load(code)
	f:storeg(C.errs.code)
	f:load(line)
	f:storeg(C.errs.line)
	f:load(arg)
	f:storeg(C.errs.arg)
	f:load(n)
	f:storeg(C.errs.n)
	f:throw(C.errtag)
end)
semerr.name = 'lcode.semerr'
function C.semerr(f, code, line, arg, n)
	f:i32(code)
	line(f)
	if arg then
		arg(f)
	else
		f:refnull(M.heap.eq)
	end
	if n then
		n(f)
	else
		f:i32(0)
	end
	f:call(semerr)
end

-- Names

local function vget(f, field)
	f:structget(var, field)
end
-- kind is a number, or nil & kindlocal a local holding it
local function newvar(f, name, vfs, kind, idx, attrib, key, kindlocal)
	name(f)
	vfs(f)
	if kind then
		f:i32(kind)
	else
		f:load(kindlocal)
	end
	idx(f)
	attrib(f)
	f:i32(0)
	key(f)
	f:refnull(var)
	f:structnew(var)
end
-- Put v in scope
local addvar = func(M.ref(var), void, function(f, v)
	f:load(v)
	f:loadg(G.names)
	f:load(v)
	vget(f, 'name')
	f:call(tblget)
	f:refcast(Rvar)
	f:structset(var, 'prev')
	f:loadg(G.names)
	f:load(v)
	vget(f, 'name')
	f:load(v)
	f:call(tblset)
	f:loadg(G.scopevars)
	f:load(v)
	f:call(C.vlpush)
end)
-- Declare a local or param of the current function. key is where its name is in the source.
-- Pass 2 knows from pass 1 if it's captured, & a captured local's slot
C.declare = func(R.str, i32, i32, i32, M.ref(var), function(f, name, kind, attrib, key)
	local v = f:locals(M.ref(var))
	local c = f:locals(LV)
	local idx = f:locals(i32)
	f:i32(-1)
	f:store(idx)
	f:load(kind)
	f:i32(K.param)
	f:eq()
	f:iff(function()
		fget(f, 'nparams')
		f:store(idx)
		fset(f, 'nparams', function()
			fget(f, 'nparams')
			f:i32(1)
			f:add()
		end)
	end)
	newvar(f, function() f:load(name) end, function() f:loadg(G.cfs) end, nil,
		function() f:load(idx) end, function() f:load(attrib) end, function() f:load(key) end, kind)
	f:store(v)
	ifpass2(f, function()
		f:loadg(G.capt)
		f:load(key)
		f:refi31()
		f:call(tblget)
		f:tee(c)
		f:refisnull()
		f:eqz()
		f:iff(function()
			f:load(v)
			f:i32(1)
			f:structset(var, 'captured')
			f:load(kind)
			f:i32(K.loc)
			f:eq()
			f:iff(function()
				f:load(v)
				f:load(c)
				C.toi32(f)
				f:structset(var, 'idx')
			end)
		end)
	end)
	fget(f, 'decls')
	f:load(v)
	f:call(C.vlpush)
	f:load(v)
	f:call(addvar)
	f:load(v)
end)
C.declare.name = 'lcode.declare'
-- Declare global name, kind global or strict, see bcgen's globaldecl.
-- Declaring a name also makes undeclared names an error, unless global * did something else
C.globaldecl = func(R.str, i32, i32, void, function(f, name, kind, attrib)
	newvar(f, function() f:load(name) end, function() f:refnull(fs) end, nil,
		function() f:i32(-1) end, function() f:load(attrib) end, function() f:i32(-1) end, kind)
	f:call(addvar)
end)
local globaldecl = C.globaldecl
-- global x for a name x: also puts in the strict marker, unless * has one
C.globalname = func(R.str, i32, void, function(f, name, attrib)
	f:load(name)
	f:i32(K.global)
	f:load(attrib)
	f:call(globaldecl)
	f:loadg(G.names)
	f:call(S'*')
	f:call(tblget)
	f:refisnull()
	f:iff(function()
		f:call(S'*')
		f:i32(K.strict)
		f:i32(0)
		f:call(globaldecl)
	end)
end)
-- Leave a scope: names declared since scopevars had n go
C.popnames = func(i32, void, function(f, n)
	local v = f:locals(Rvar)
	f:block(function(done)
		f:loop(function(loop)
			f:loadg(G.scopevars)
			C.vllen(f)
			f:load(n)
			f:leu()
			f:brif(done)
			f:loadg(G.scopevars)
			f:loadg(G.scopevars)
			C.vllen(f)
			f:i32(1)
			f:sub()
			f:structset(stack, 'len')
			f:loadg(G.scopevars)
			f:loadg(G.scopevars)
			C.vllen(f)
			C.vlget(f)
			f:refcast(Rvar)
			f:store(v)
			f:loadg(G.names)
			f:load(v)
			vget(f, 'name')
			f:load(v)
			vget(f, 'prev')
			f:call(tblset)
			f:br(loop)
		end)
	end)
end)

-- What a name use refers to, from resolve: the var (the _ENV var for a global) & if it's a global
G.rvar = M.global(Rvar, true)
G.rglob = M.global(i32, true)
G.rattr = M.global(i32, true)
-- Look name up, like bcgen's usename. Errors for undeclared names. Pass 1 notes captures
C.resolve = func(R.str, i32, void, function(f, name, line)
	local v = f:locals(Rvar)
	f:i32(0)
	f:storeg(G.rattr)
	f:loadg(G.names)
	f:load(name)
	f:call(tblget)
	f:refcast(Rvar)
	f:tee(v)
	f:refisnull()
	f:iff(function()
		f:loadg(G.names)
		f:call(S'*')
		f:call(tblget)
		f:refcast(Rvar)
		f:tee(v)
		f:refisnull()
		f:eqz()
		f:iff(function()
			f:load(v)
			vget(f, 'kind')
			f:i32(K.strict)
			f:eq()
			f:iff(function()
				C.semerr(f, C.E.undeclared, function() f:load(line) end, function() f:load(name) end)
			end)
		end)
	end)
	f:load(v)
	f:refisnull()
	f:iff(i32, function()
		f:i32(1)
	end, function()
		f:load(v)
		vget(f, 'attrib')
		f:storeg(G.rattr)
		f:load(v)
		vget(f, 'kind')
		f:i32(K.global)
		f:geu()
	end)
	f:storeg(G.rglob)
	f:loadg(G.rglob)
	f:iff(function()
		f:loadg(G.names)
		f:call(S'_ENV')
		f:call(tblget)
		f:refcast(Rvar)
		f:tee(v)
		vget(f, 'kind')
		f:i32(K.global)
		f:geu()
		f:iff(function()
			C.semerr(f, C.E.envglobal, function() f:load(line) end, function() f:load(name) end)
		end)
	end)
	f:load(v)
	f:storeg(G.rvar)
	-- used from another function: it lives in a box
	f:load(v)
	vget(f, 'fs')
	f:loadg(G.cfs)
	f:refeq()
	f:eqz()
	f:iff(function()
		f:load(v)
		f:i32(1)
		f:structset(var, 'captured')
	end)
end)
C.resolve.name = 'lcode.resolve'

-- Index of v in the current function: a free's index, a param's or a local's slot
C.nameidx = func(M.ref(var), i32, function(f, v)
	local frees = f:locals(Rvl)
	local i, n = f:locals(i32, 2)
	f:load(v)
	vget(f, 'fs')
	f:loadg(G.cfs)
	f:refeq()
	f:eqz()
	f:iff(function()
		fget(f, 'frees')
		f:tee(frees)
		C.vllen(f)
		f:store(n)
		f:block(function(notfound)
			f:loop(function(loop)
				f:load(i)
				f:load(n)
				f:geu()
				f:brif(notfound)
				f:load(frees)
				f:load(i)
				C.vlget(f)
				f:load(v)
				f:refeq()
				f:iff(function()
					f:load(i)
					f:ret()
				end)
				f:load(i)
				f:i32(1)
				f:add()
				f:store(i)
				f:br(loop)
			end)
		end)
		f:load(frees)
		f:load(v)
		f:call(C.vlpush)
		f:load(n)
		f:ret()
	end)
	f:load(v)
	vget(f, 'kind')
	f:i32(K.loc)
	f:eq()
	f:load(v)
	vget(f, 'idx')
	f:i32(0)
	f:lts()
	f:band()
	f:iff(function()
		f:load(v)
		fget(f, 'nlocals')
		f:structset(var, 'idx')
		fset(f, 'nlocals', function()
			fget(f, 'nlocals')
			f:i32(1)
			f:add()
		end)
	end)
	f:load(v)
	vget(f, 'idx')
end)
C.nameidx.name = 'lcode.nameidx'
-- a temp local slot
function C.newtemp(f)
	fget(f, 'nlocals')
	fset(f, 'nlocals', function()
		fget(f, 'nlocals')
		f:i32(1)
		f:add()
	end)
end

-- What a var is, for error messages: "local 'x'", "upvalue 'x'" or "global 'x'"
C.scopedesc = func(M.ref(var), i32, R.str, LV, function(f, v, glob, name)
	f:load(glob)
	f:iff(M.ref(str), function()
		f:call(S"global '")
	end, function()
		f:load(v)
		vget(f, 'fs')
		f:loadg(G.cfs)
		f:refeq()
		f:iff(M.ref(str), function()
			f:call(S"local '")
		end, function()
			f:call(S"upvalue '")
		end)
	end)
	f:load(name)
	f:call(mkdesc)
end)

-- Load or store name, by its var & whether it's a global, see bcgen's opnamety
local function opvar(f, isstore)
	return func(M.ref(var), i32, R.str, void, function(f, v, glob, name)
		local idx = f:locals(i32)
		local env = f:locals(M.ref(var))
		f:load(glob)
		f:iff(function()
			-- _ENV[name]. _ENV is always loaded
			f:load(v)
			f:i32(0)
			f:call(S'_ENV')
			f:call(C.loadvarraw)
			loadk(f, function() f:load(name) end)
			op(f, isstore and bc.TblSet or bc.Idx)
			opname(f, function()
				list(f, { function()
					f:load(v)
					f:i32(0)
					f:call(S'_ENV')
					f:call(C.scopedesc)
				end })
			end)
			f:ret()
		end)
		f:load(v)
		f:call(C.nameidx)
		f:store(idx)
		local function emit(o)
			f:i32(o)
			f:call(emitop)
			f:load(idx)
			f:call(emitarg)
		end
		f:load(v)
		vget(f, 'captured')
		f:iff(function()
			f:load(v)
			vget(f, 'fs')
			f:loadg(G.cfs)
			f:refeq()
			f:eqz()
			f:iff(function()
				emit(isstore and bc.StoreFreeBox or bc.LoadFreeBox)
			end, function()
				f:load(v)
				vget(f, 'kind')
				f:i32(K.param)
				f:eq()
				f:iff(function()
					emit(isstore and bc.StoreParamBox or bc.LoadParamBox)
				end, function()
					emit(isstore and bc.StoreLocalBox or bc.LoadLocalBox)
				end)
			end)
		end, function()
			f:load(v)
			vget(f, 'kind')
			f:i32(K.param)
			f:eq()
			f:iff(function()
				emit(isstore and bc.StoreParam or bc.LoadParam)
			end, function()
				emit(isstore and bc.StoreLocal or bc.LoadLocal)
			end)
		end)
	end)
end
C.loadvarraw = opvar(nil, false)
C.storevar = opvar(nil, true)
-- Load name & note what it is in desc
C.loadvar = func(M.ref(var), i32, R.str, void, function(f, v, glob, name)
	f:load(v)
	f:load(glob)
	f:load(name)
	f:call(C.loadvarraw)
	ifpass2(f, function()
		f:load(v)
		f:load(glob)
		f:load(name)
		f:call(C.scopedesc)
		f:storeg(G.desc)
	end)
end)

-- A local comes into scope at the current pc
C.activate = func(M.ref(var), void, function(f, v)
	local lv = f:locals(M.ref(lvar))
	f:load(v)
	pc(f)
	f:i32(0)
	f:structnew(lvar)
	f:store(lv)
	fget(f, 'locvars')
	f:load(lv)
	f:call(C.vlpush)
	fget(f, 'actives')
	f:load(lv)
	f:call(C.vlpush)
end)
-- Locals in scope past the first n go out of scope here
C.deactivate = func(i32, void, function(f, n)
	local a = f:locals(Rvl)
	fget(f, 'actives')
	f:store(a)
	f:block(function(done)
		f:loop(function(loop)
			f:load(a)
			C.vllen(f)
			f:load(n)
			f:leu()
			f:brif(done)
			f:load(a)
			f:load(a)
			C.vllen(f)
			f:i32(1)
			f:sub()
			f:structset(stack, 'len')
			f:load(a)
			f:load(a)
			C.vllen(f)
			C.vlget(f)
			f:refcast(M.ref(lvar))
			pc(f)
			f:structset(lvar, 'endpc')
			f:br(loop)
		end)
	end)
end)
-- The last k locals were declared last first, put them in order
C.inorder = func(i32, void, function(f, k)
	local i, j, m = f:locals(i32, 3)
	local l = f:locals(Rvl)
	local t = f:locals(LV)
	for _, field in ipairs{ 'actives', 'locvars' } do
		fget(f, field)
		f:store(l)
		f:i32(0)
		f:store(i)
		f:loop(function(loop)
			f:load(i)
			f:load(k)
			f:i32(1)
			f:shru()
			f:ltu()
			f:iff(function()
				f:load(l)
				C.vllen(f)
				f:load(k)
				f:sub()
				f:load(i)
				f:add()
				f:store(j)
				f:load(l)
				C.vllen(f)
				f:i32(1)
				f:sub()
				f:load(i)
				f:sub()
				f:store(m)
				f:load(l)
				f:load(j)
				C.vlget(f)
				f:store(t)
				f:load(l)
				f:structget(stack, 'arr')
				f:load(j)
				f:load(l)
				f:load(m)
				C.vlget(f)
				f:arrayset(vals)
				f:load(l)
				f:structget(stack, 'arr')
				f:load(m)
				f:load(t)
				f:arrayset(vals)
				f:load(i)
				f:i32(1)
				f:add()
				f:store(i)
				f:br(loop)
			end)
		end)
	end
end)
-- A captured local gets a fresh box each time it's declared, so closures made in a loop each keep
-- their own variable
C.boxvar = func(M.ref(var), void, function(f, v)
	f:load(v)
	vget(f, 'captured')
	f:load(v)
	vget(f, 'kind')
	f:i32(K.loc)
	f:eq()
	f:band()
	f:iff(function()
		op(f, bc.BoxLocal, function()
			f:load(v)
			f:call(C.nameidx)
		end)
	end)
end)
-- Box, store what's on the stack & come into scope
C.declvar = func(M.ref(var), void, function(f, v)
	f:load(v)
	f:call(C.boxvar)
	f:load(v)
	f:i32(0)
	f:load(v)
	vget(f, 'name')
	f:call(C.storevar)
	f:load(v)
	f:call(C.activate)
end)
-- Raise "global 'x' already defined" if global x isn't nil, before global x = e sets it
C.checkglobal = func(M.ref(var), i32, R.str, void, function(f, v, glob, name)
	f:load(v)
	f:load(glob)
	f:load(name)
	f:call(C.loadvar)
	f:refnull(M.heap.eq)
	f:storeg(G.desc)
	op(f, bc.ErrNNil, function()
		f:load(name)
		f:call(konst)
	end)
end)

-- <close>: close the k newest <close> variables with the prelude's helper. Gives where k's const index
-- is, so a goto can patch it once the count is known
C.tbcclose = func(i32, i32, i32, function(f, k, force)
	local kpc = f:locals(i32)
	f:i32(-1)
	f:store(kpc)
	f:load(k)
	f:i32(0)
	f:gts()
	f:load(force)
	f:bor()
	f:iff(function()
		loadk(f, function() f:loadg(G.htbcclose) end)
		pc(f)
		f:i32(1)
		f:add()
		f:store(kpc)
		loadki(f, function() f:load(k) end)
		op(f, bc.Call, 0, 1, 1)
		opname(f, function()
			list(f, { function() f:call(S"metamethod 'close'") end }, true)
		end)
	end)
	f:load(kpc)
end)
-- After a <close> variable's value is stored, check it can be closed & keep it to close later.
-- emit(f) pushes the value
function C.tbcpush(f, emit, name)
	loadk(f, function() f:loadg(G.htbcpush) end)
	emit(f)
	loadk(f, name)
	op(f, bc.Call, 0, 1, 2)
	opname(f, function()
		list(f, { function() f:refnull(M.heap.eq) end }, true)
	end)
	fset(f, 'tbcn', function()
		fget(f, 'tbcn')
		f:i32(1)
		f:add()
	end)
end

-- Expressions. What the last expression parsed made, like lparser.c's expdesc. Most kinds aren't emitted
-- yet: how many values are wanted, & so what to emit, is only known once whatever comes after is seen.
-- Only the newest expression is ever held, so this is globals
local EK = {
	stack = 1, -- one value, emitted
	knil = 2, kfalse = 3, ktrue = 4,
	const = 5, -- LoadConst ev
	func = 6, -- a function, ev is its fs
	varg = 7, -- ...
	call = 8, -- a call, see the chain below
	name = 9, -- a variable: evar, eglob & ev its name, eattr its attrib
	index = 10, -- table & key are on the stack. ed is what made the table, ev the key if it's a name
}
C.EK = EK
G.ek = M.global(i32, true)
G.ev = M.global(LV, true)
G.evar = M.global(Rvar, true)
G.eglob = M.global(i32, true)
G.eattr = M.global(i32, true)
-- line where bcgen would emit it, & the line for padding to the count wanted
G.eline = M.global(i32, true)
G.epad = M.global(i32, true)
G.ed = M.global(LV, true)
-- it's a prefix & suffix chain (its desc names it), it's an operator's result
G.echain = M.global(i32, true)
G.eisop = M.global(i32, true)
-- A call not emitted yet, with the calls whose last arg it is. A call op takes each one's arg count,
-- outermost first: ccounts & cdescs are innermost first. cvarg: the innermost is ..., cline: line of the call
G.ccounts = M.global(Ril, true)
G.cdescs = M.global(Rvl, true)
G.cvarg = M.global(i32, true)
G.cline = M.global(i32, true)

function C.chainreset(f)
	f:loadg(G.ccounts)
	f:i32(0)
	f:structset(ilist, 'len')
	f:loadg(G.cdescs)
	f:i32(0)
	f:structset(stack, 'len')
	f:i32(0)
	f:storeg(G.cvarg)
end
-- emit opcode (opcodevarg if the chain ends in ...), first(f) pushing its first arg, then the counts
local function emitchain(f, opcode, opcodevarg, first)
	local i = f:locals(i32)
	f:loadg(G.cvarg)
	f:iff(i32, function() f:i32(opcodevarg) end, function() f:i32(opcode) end)
	f:call(emitop)
	first(f)
	f:call(emitarg)
	f:loadg(G.ccounts)
	f:structget(ilist, 'len')
	f:tee(i)
	f:call(emitarg)
	f:loop(function(loop)
		f:load(i)
		f:iff(function()
			f:load(i)
			f:i32(1)
			f:sub()
			f:store(i)
			f:loadg(G.ccounts)
			f:load(i)
			C.ilget(f)
			f:call(emitarg)
			f:br(loop)
		end)
	end)
	opname(f, function()
		local t = f:locals(R.tbl)
		local j = f:locals(i32)
		f:call(alloc.newtbl)
		f:store(t)
		f:loadg(G.cdescs)
		C.vllen(f)
		f:store(i)
		f:i32(1)
		f:store(j)
		f:loop(function(loop)
			f:load(i)
			f:iff(function()
				f:load(i)
				f:i32(1)
				f:sub()
				f:store(i)
				f:load(t)
				f:load(j)
				f:refi31()
				f:loadg(G.cdescs)
				f:load(i)
				C.vlget(f)
				orfalse(f)
				f:call(tblset)
				f:load(j)
				f:i32(1)
				f:add()
				f:store(j)
				f:br(loop)
			end)
		end)
		f:load(t)
		f:call(S'call')
		alloc.ltrue(f)
		f:call(tblset)
		f:load(t)
	end)
end
C.emitchain = emitchain

-- LoadFunc of fs child: its frees from this function, then the proto
local loadfunc = func(M.ref(fs), void, function(f, child)
	local frees = f:locals(Rvl)
	local i, idx = f:locals(i32, 2)
	local v = f:locals(M.ref(var))
	f:load(child)
	f:structget(fs, 'frees')
	f:store(frees)
	f:loop(function(loop)
		f:load(i)
		f:load(frees)
		C.vllen(f)
		f:ltu()
		f:iff(function()
			f:load(frees)
			f:load(i)
			C.vlget(f)
			f:refcast(M.ref(var))
			f:tee(v)
			f:call(C.nameidx)
			f:store(idx)
			f:load(v)
			vget(f, 'fs')
			f:loadg(G.cfs)
			f:refeq()
			f:eqz()
			f:iff(i32, function()
				f:i32(bc.LoadFree)
			end, function()
				f:load(v)
				vget(f, 'kind')
				f:i32(K.param)
				f:eq()
				f:iff(i32, function() f:i32(bc.LoadParam) end, function() f:i32(bc.LoadLocal) end)
			end)
			f:call(emitop)
			f:load(idx)
			f:call(emitarg)
			f:load(i)
			f:i32(1)
			f:add()
			f:store(i)
			f:br(loop)
		end)
	end)
	op(f, bc.LoadFunc, function()
		f:load(frees)
		C.vllen(f)
	end, function()
		-- pass 1 has no proto, the fs stands in
		f:load(child)
		f:structget(fs, 'proto')
		f:load(child)
		f:loadg(G.pass)
		f:i32(2)
		f:eq()
		f:select(LV)
		f:call(konstnew)
	end)
end)

-- Emit the held expression so it gives n values (-1: as many as it has, a call or ... then stays held).
-- Gives how many it gave, -1 when it's still held
C.discharge = func(i32, i32, function(f, n)
	local c, pl = f:locals(i32, 2)
	f:loadg(G.curline)
	f:store(pl)
	f:loadg(G.eline)
	f:storeg(G.curline)
	f:i32(1)
	f:store(c)
	f:block(function(pad)
		f:block(function(zero)
			local function k(kind, body)
				f:loadg(G.ek)
				f:i32(kind)
				f:eq()
				f:iff(body)
			end
			-- these give nothing when nothing is wanted
			f:load(n)
			f:eqz()
			f:loadg(G.ek)
			f:i32(EK.knil)
			f:geu()
			f:loadg(G.ek)
			f:i32(EK.varg)
			f:leu()
			f:band()
			f:band()
			f:brif(zero)
			k(EK.knil, function()
				op(f, bc.LoadNil)
			end)
			k(EK.kfalse, function()
				op(f, bc.LoadFalse)
			end)
			k(EK.ktrue, function()
				op(f, bc.LoadTrue)
			end)
			k(EK.const, function()
				loadk(f, function() f:loadg(G.ev) end)
			end)
			k(EK.func, function()
				f:loadg(G.ev)
				f:refcast(M.ref(fs))
				f:call(loadfunc)
			end)
			k(EK.varg, function()
				fget(f, 'vargvar')
				f:refisnull()
				f:iff(function()
					f:load(n)
					f:i32(-1)
					f:eq()
					f:iff(function()
						C.chainreset(f)
						f:i32(1)
						f:storeg(G.cvarg)
						f:i32(EK.call)
						f:storeg(G.ek)
						f:i32(-1)
						f:store(c)
						f:br(zero)
					end)
					op(f, bc.LoadVarg, function() f:load(n) end)
					f:load(n)
					f:store(c)
					f:br(pad)
				end)
				-- with a named vararg table t, ... is t[1..t.n]: call the prelude's helper on t
				loadk(f, function() f:loadg(G.hvargunpack) end)
				fget(f, 'vargvar')
				f:refcast(M.ref(var))
				f:i32(0)
				fget(f, 'vargvar')
				f:refcast(M.ref(var))
				vget(f, 'name')
				f:call(C.loadvar)
				f:refnull(M.heap.eq)
				f:storeg(G.desc)
				C.chainreset(f)
				f:loadg(G.ccounts)
				f:i32(1)
				f:call(C.ilpush)
				f:loadg(G.cdescs)
				f:refnull(M.heap.eq)
				f:call(C.vlpush)
				f:loadg(G.eline)
				f:storeg(G.cline)
				f:i32(EK.call)
				f:storeg(G.ek)
			end)
			k(EK.call, function()
				f:load(n)
				f:i32(-1)
				f:eq()
				f:iff(function()
					f:i32(-1)
					f:store(c)
					f:br(zero)
				end)
				f:loadg(G.cline)
				f:storeg(G.curline)
				emitchain(f, bc.Call, bc.CallVarg, function() f:load(n) end)
				f:load(n)
				f:store(c)
			end)
			k(EK.name, function()
				f:loadg(G.evar)
				f:refasnonnull()
				f:loadg(G.eglob)
				f:loadg(G.ev)
				f:refcast(R.str)
				f:call(C.loadvar)
			end)
			k(EK.index, function()
				op(f, bc.Idx)
				opname(f, function()
					list(f, { function() f:loadg(G.ed) end })
				end)
				f:loadg(G.ev)
				f:refisnull()
				f:iff(LV, function()
					f:refnull(M.heap.eq)
				end, function()
					f:call(S"field '")
					f:loadg(G.ev)
					f:refcast(R.str)
					f:call(mkdesc)
				end)
				f:storeg(G.desc)
			end)
			f:br(pad)
		end)
		-- nothing emitted: c is 0, or -1 when it's still held
		f:load(c)
		f:i32(1)
		f:eq()
		f:iff(function()
			f:i32(0)
			f:store(c)
		end)
		f:load(c)
		f:i32(-1)
		f:eq()
		f:iff(function()
			f:load(pl)
			f:storeg(G.curline)
			f:i32(-1)
			f:ret()
		end)
	end)
	f:i32(EK.stack)
	f:storeg(G.ek)
	-- too few values: pad with nil. too many: pop the extra
	f:load(n)
	f:i32(-1)
	f:ne()
	f:iff(function()
		f:loadg(G.epad)
		f:storeg(G.curline)
		f:loop(function(loop)
			f:load(c)
			f:load(n)
			f:lts()
			f:iff(function()
				op(f, bc.LoadNil)
				f:load(c)
				f:i32(1)
				f:add()
				f:store(c)
				f:br(loop)
			end)
		end)
		f:loop(function(loop)
			f:load(c)
			f:load(n)
			f:gts()
			f:iff(function()
				op(f, bc.Pop)
				f:load(c)
				f:i32(1)
				f:sub()
				f:store(c)
				f:br(loop)
			end)
		end)
	end)
	f:load(pl)
	f:storeg(G.curline)
	f:load(c)
end)
C.discharge.name = 'lcode.discharge'
-- Store into the held expression, a name or an index
C.storeheld = func(function(f)
	local pl = f:locals(i32)
	f:loadg(G.curline)
	f:store(pl)
	f:loadg(G.eline)
	f:storeg(G.curline)
	f:loadg(G.ek)
	f:i32(EK.name)
	f:eq()
	f:iff(function()
		f:loadg(G.eattr)
		f:iff(function()
			C.semerr(f, C.E.const, function() f:loadg(G.eline) end, function() f:loadg(G.ev) end)
		end)
		f:loadg(G.evar)
		f:refasnonnull()
		f:loadg(G.eglob)
		f:loadg(G.ev)
		f:refcast(R.str)
		f:call(C.storevar)
	end, function()
		op(f, bc.TblSet)
		opname(f, function()
			list(f, { function() f:loadg(G.ed) end })
		end)
	end)
	f:load(pl)
	f:storeg(G.curline)
end)

-- Functions

-- Start compiling a function. key is where it starts in the source
C.openfunc = func(i32, i32, LV, void, function(f, key, line, fname)
	local n = f:locals(M.ref(fs))
	f:structnewdefault(fs)
	f:tee(n)
	f:loadg(G.cfs)
	f:structset(fs, 'prev')
	f:load(n)
	f:storeg(G.cfs)
	fset(f, 'bc', function()
		f:i32(64)
		f:call(newbbuf)
	end)
	for _, l in ipairs{ 'consts', 'frees', 'actives', 'locvars', 'decls', 'gotos' } do
		fset(f, l, function() f:call(C.newvl) end)
	end
	fset(f, 'kmap', function() f:call(alloc.newtbl) end)
	fset(f, 'kfmap', function() f:call(alloc.newtbl) end)
	fset(f, 'lineinfo', function() f:call(C.newil) end)
	ifpass2(f, function()
		fset(f, 'opnames', function() f:call(alloc.newtbl) end)
	end)
	fset(f, 'targets', function()
		f:i32(64)
		f:arraynewdefault(bytes)
	end)
	fset(f, 'lastop', function() f:i32(-2) end)
	fset(f, 'prevop', function() f:i32(-2) end)
	fset(f, 'key', function() f:load(key) end)
	fset(f, 'linedef', function() f:load(line) end)
	fset(f, 'fname', function() f:load(fname) end)
	f:i32(0)
	f:storeg(G.curline)
end)
-- Box captured params & locals, at the start of the function. Captured locals get their slots first.
-- Pass 2 only, pass 1 doesn't know yet
C.prologue = func(function(f)
	local d = f:locals(Rvl)
	local l = f:locals(Ril)
	local v = f:locals(M.ref(var))
	local i, slot = f:locals(i32, 2)
	f:loadg(G.pass)
	f:i32(1)
	f:eq()
	f:iff(function()
		f:ret()
	end)
	fget(f, 'decls')
	f:store(d)
	f:loop(function(loop)
		f:load(i)
		f:load(d)
		C.vllen(f)
		f:ltu()
		f:iff(function()
			f:load(d)
			f:load(i)
			C.vlget(f)
			f:refcast(M.ref(var))
			f:tee(v)
			vget(f, 'kind')
			f:i32(K.param)
			f:eq()
			f:load(v)
			vget(f, 'captured')
			f:band()
			f:iff(function()
				op(f, bc.BoxParam, function()
					f:load(v)
					vget(f, 'idx')
				end)
			end)
			f:load(i)
			f:i32(1)
			f:add()
			f:store(i)
			f:br(loop)
		end)
	end)
	f:loadg(G.fcapt)
	fget(f, 'key')
	f:refi31()
	f:call(tblget)
	f:refcast(Ril)
	f:tee(l)
	f:refisnull()
	f:iff(function()
		f:ret()
	end)
	f:i32(0)
	f:store(i)
	f:loop(function(loop)
		f:load(i)
		f:load(l)
		f:structget(ilist, 'len')
		f:ltu()
		f:iff(function()
			C.newtemp(f)
			f:store(slot)
			f:loadg(G.capt)
			f:load(l)
			f:load(i)
			C.ilget(f)
			f:refi31()
			f:load(slot)
			f:refi31()
			f:call(tblset)
			op(f, bc.BoxLocal, function() f:load(slot) end)
			f:load(i)
			f:i32(1)
			f:add()
			f:store(i)
			f:br(loop)
		end)
	end)
end)

return C

local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, R, typeof, tbl, str, int, float, vals, bytes, functy, box, coro, stack, frames =
	alloc.types, alloc.R, alloc.typeof, alloc.tbl, alloc.str, alloc.int, alloc.float, alloc.vals, alloc.bytes,
	alloc.functy, alloc.box, alloc.coro, alloc.stack, alloc.frames
local lnil, lfalse, ltrue = alloc.lnil, alloc.lfalse, alloc.ltrue

local _table = require '_table'
local tblget, tblset, tbllen = _table.tblget, _table.tblset, _table.tbllen

local _stack = require 'stack'
local tmppush, tmppop, nthtmp, extendtmp, stacklen, sget, sset, df, fget, fset =
	_stack.tmppush, _stack.tmppop, _stack.nthtmp, _stack.extendtmp, _stack.stacklen, _stack.sget, _stack.sset,
	_stack.df, _stack.fget, _stack.fset

local _string = require '_string'
local _obj = require 'obj'

local ops = require 'bc'

local rt = require 'rt'
local microbc = require 'microbc'

local frame = require 'frame'
local objframe, calltypes, getf, setf = frame.objframe, frame.calltypes, frame.getf, frame.setf

-- Start running fn on the running coro, its args are what's on the stack.
-- The frame is type init, so returning from fn ends eval
local init = func(V, void, function(f, fnv)
	f:i32(df.sizeof * 8)
	f:call(alloc.newframes)
	f:storeg(gframes)
	f:loadg(oluastack)
	f:loadg(gframes)
	f:structset(coro, 'data')
	f:call(_stack.fpush)
	setf(f, 'type', function() f:i32(calltypes.init) end)
	setf(f, 'retc', function() f:i32(frame.RETALL) end)
	f:load(fnv)
	f:refcast(R.functy)
	f:call(frame.framefor)
end)

local mopcomp = {}
local function isfloat(mty)
	return mty == 'f32' or mty == 'f64'
end
local function defMop(opName, func)
	mopcomp[assert(microbc.mops[opName], 'defMop: unknown mop ' .. opName)] = func
end
local microTypeToWasmTypeTable = {
	i32 = i32,
	i64 = i64,
	f32 = f32,
	f64 = f64,
	obj = V,
	int = R.int,
	float = R.float,
	str = R.str,
	tbl = R.tbl,
}
local function microTypeToWasmType(mty)
	if mty then
		return assert(microTypeToWasmTypeTable[mty], "Cannot resolve wasm type for microbc type")
	else
		return void
	end
end
local function emitOp(ctx, scopes, f)
	for i=1,#ctx.code do
		ctx.code[i](f, scopes)
	end
end
-- Queue code to emit. Analysis runs first, so wasm locals exist by the time code is emitted
local function cg(ctx, fn)
	ctx.code[#ctx.code+1] = fn
end
-- A register is a table whose .r gets filled in with a wasm local by genLocals.
-- Ops never run at the same time, so each op numbers its registers from 1 & they're shared between ops
local function newreg(ctx, mty)
	local wty = microTypeToWasmType(mty)
	local rtbl = ctx.regdef[wty]
	if not rtbl then
		rtbl = {}
		ctx.regdef[wty] = rtbl
		ctx.regtys[#ctx.regtys+1] = wty
	end
	local n = (ctx.regn[wty] or 0) + 1
	ctx.regn[wty] = n
	local r = rtbl[n]
	if not r then
		r = {}
		rtbl[n] = r
	end
	return r
end
-- Leave a node's value on the wasm stack.
-- A statement's value was put in a register where the statement ran, unless it's inlined here.
-- Pure nodes are computed again at each use
local function resolve(ctx, node)
	if node.stmt and not ctx.inline[node] then
		local r = assert(ctx.temps[node], 'statement value used before its statement ran')
		cg(ctx, function(f)
			f:load(r.r)
		end)
	else
		mopcomp[node.op](node, ctx)
	end
end
local function genstmt(ctx, node)
	if ctx.inline[node] then
		return
	end
	mopcomp[node.op](node, ctx)
	if microTypeToWasmType(node.out) ~= void then
		if (ctx.uses[node] or 0) == 0 then
			cg(ctx, function(f)
				f:drop()
			end)
		else
			local r = newreg(ctx, node.out)
			ctx.temps[node] = r
			cg(ctx, function(f)
				f:store(r.r)
			end)
		end
	end
end
-- Code made by fn(subctx), kept apart so it can go inside an if/loop
local function thunk(ctx, fn)
	local subctx = setmetatable({
		code = {},
	}, { __index = ctx })
	fn(subctx)
	return function(f, scopes)
		emitOp(subctx, scopes, f)
	end
end
-- A block's statements, then its result if wty isn't void
local function genblock(ctx, blk, wty)
	return thunk(ctx, function(subctx)
		for _, s in ipairs(blk.stmts) do
			genstmt(subctx, s)
		end
		if wty ~= void then
			resolve(subctx, blk.result)
		end
	end)
end

-- How many times each node gets evaluated: pure nodes count again at each use,
-- a statement's args only count once, where the statement runs
local function countuses(uses, node)
	if type(node) ~= 'table' then
		return
	end
	uses[node] = (uses[node] or 0) + 1
	if not node.stmt then
		for i=1,#node do
			countuses(uses, node[i])
		end
	end
end
local function countblock(uses, blk)
	for _, s in ipairs(blk.stmts) do
		for i=1,#s do
			countuses(uses, s[i])
		end
		for _, sub in ipairs(s.blocks or {}) do
			countblock(uses, sub)
		end
	end
	countuses(uses, blk.result)
end
-- Is v the first thing with a side effect that evaluating node's args runs?
-- Args are evaluated in order. Values of other statements are register loads, so they don't count.
-- Nested blocks aren't looked at, they may not run
local function early(node, v)
	for i=1,#node do
		local a = node[i]
		if a == v then
			return true
		elseif type(a) == 'table' then
			if not a.stmt then
				local r = early(a, v)
				if r ~= nil then
					return r
				end
			end
			if node.argfx then
				return false
			end
		end
	end
	return nil
end
-- A statement value used once, by the next statement before it does anything else,
-- can be computed right there instead of going through a register
local function findinline(uses, inline, blk)
	local stmts = blk.stmts
	for k, s in ipairs(stmts) do
		if uses[s] == 1 and microTypeToWasmType(s.out) ~= void then
			local nxt = stmts[k+1]
			if nxt then
				inline[s] = early(nxt, s) == true
			elseif blk.result then
				inline[s] = blk.result == s or (not blk.result.stmt and early(blk.result, s) == true)
			end
		end
		for _, sub in ipairs(s.blocks or {}) do
			findinline(uses, inline, sub)
		end
	end
end
-- Bytes of bytecode args read by an op, from its highest Arg index
local function argsize(blk)
	local n = 0
	microbc.walk(blk, function(node)
		if node.op == microbc.mops.Arg then
			n = math.max(n, (node[1] + 1) * 4)
		end
	end)
	return n
end
-- L holds eval's existing wasm locals
local function mkcgctx(f, L)
	return {
		f = f,
		regdef = {},
		regtys = {},
		bc = { r = L.bc },
		pc = { r = L.pc },
		base = { r = L.base },
		objbase = { r = L.objbase },
		locbase = { r = L.locbase },
	}
end
local function genOp(ctx, op)
	local blk = assert(microbc.ops[op], 'genOp: no microcode for op')
	local uses, inline = {}, {}
	countblock(uses, blk)
	findinline(uses, inline, blk)
	local subctx = setmetatable({
		uses = uses,
		inline = inline,
		temps = {},
		code = {},
		regn = {},
	}, { __index = ctx })
	-- Bytes of bytecode args, mops that leave the op early need it to find the next op
	local argoffset = argsize(blk)
	subctx.argoffset = argoffset
	for _, s in ipairs(blk.stmts) do
		genstmt(subctx, s)
	end
	return function(scopes)
		local f = ctx.f
		emitOp(subctx, scopes, f)
		-- SetPc branches out before this, so jumps skip it
		if argoffset > 0 then
			f:load(ctx.pc.r)
			f:i32(argoffset)
			f:add()
			f:store(ctx.pc.r)
		end
		f:br(scopes.nop)
	end
end

-- Narrow an object's type: a cast, which can't fail where microbc uses it
defMop('As', function(mop, ctx)
	resolve(ctx, mop[1])
	local t = microTypeToWasmType(mop[2])
	if t ~= V then
		cg(ctx, function(f)
			f:refcast(t)
		end)
	end
end)
defMop('Int', function(mop, ctx)
	cg(ctx, function(f)
		f:i32(mop[1])
	end)
end)
defMop('Int64', function(mop, ctx)
	cg(ctx, function(f)
		f:i64(mop[1])
	end)
end)
defMop('Flt', function(mop, ctx)
	cg(ctx, function(f)
		f:f32(mop[1])
	end)
end)
defMop('Flt64', function(mop, ctx)
	cg(ctx, function(f)
		f:f64(mop[1])
	end)
end)
defMop('Unbox', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:refcast(R.box)
		f:structget(box, 'val')
	end)
end)
defMop('SetBox', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:refcast(R.box)
	end)
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:structset(box, 'val')
	end)
end)
local objconst = { [NIL] = lnil, [FALSE] = lfalse, [TRUE] = ltrue }
defMop('Obj', function(mop, ctx)
	local emit = assert(objconst[mop[1]], 'Obj: unknown constant')
	cg(ctx, function(f)
		emit(f)
	end)
end)
defMop('Type', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(typeof)
	end)
end)
defMop('IsTbl', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(typeof)
		f:i32(types.tbl)
		f:eq()
	end)
end)
defMop('IsTblOrVec', function(mop, ctx)
	local r = newreg(ctx, 'i32')
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(typeof)
		f:tee(r.r)
		f:i32(types.tbl)
		f:eq()
		f:load(r.r)
		f:i32(types.vec)
		f:eq()
		f:bor()
	end)
end)
defMop('IsNumOrStr', function(mop, ctx)
	local r = newreg(ctx, 'i32')
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(typeof)
		f:tee(r.r)
		f:i32(types.float)
		f:leu()
		f:load(r.r)
		f:i32(types.str)
		f:eq()
		f:bor()
	end)
end)
defMop('LoadInt', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:structget(int, 'val')
	end)
end)
defMop('LoadFlt', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:structget(float, 'val')
	end)
end)
defMop('LoadStrLen', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:structget(str, 'bytes')
		f:arraylen()
	end)
end)
defMop('Meta', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:structget(tbl, 'meta')
	end)
end)
defMop('LoadTblLen', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(tbllen)
	end)
end)
defMop('StrCmp', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:call(_string.strcmp)
	end)
end)
defMop('LoadFuncParamc', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:refcast(R.functy)
		f:structget(functy, 'paramc')
	end)
end)
defMop('TblGet', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:call(tblget)
	end)
end)
defMop('NewTbl', function(mop, ctx)
	cg(ctx, function(f)
		f:call(alloc.newtbl)
	end)
end)
defMop('TblSet', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	resolve(ctx, mop[3])
	cg(ctx, function(f)
		f:call(tblset)
	end)
end)
defMop('Box', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(alloc.newbox)
	end)
end)
defMop('IntObjFromInt', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i64extends()
		f:call(alloc.newi64)
	end)
end)
defMop('IntObjFromInt64', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(alloc.newi64)
	end)
end)
defMop('FltObjFromFlt', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(alloc.newf64)
	end)
end)
defMop('Flt64Int', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i64truncs()
	end)
end)
defMop('Int64Flt', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:f64converts()
	end)
end)
defMop('Push', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(tmppush)
	end)
end)
defMop('Pop', function(mop, ctx)
	cg(ctx, function(f)
		f:call(tmppop)
	end)
end)
defMop('Peek', function(mop, ctx)
	cg(ctx, function(f)
		f:i32(1)
		f:call(nthtmp)
	end)
end)
defMop('SetPc', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f, scopes)
		f:store(ctx.pc.r)
		f:br(scopes.nop)
	end)
end)
-- Arg n is the nth 4 byte arg after the opcode. pc already points past the opcode
defMop('Arg', function(mop, ctx)
	cg(ctx, function(f)
		f:load(ctx.bc.r)
		f:load(ctx.pc.r)
		if mop[1] > 0 then
			f:i32(mop[1] * 4)
			f:add()
		end
		f:call(frame.bcarg)
	end)
end)
-- Slot n of the function's consts or frees, vecs in the objframe
local function defVecSlot(name, which)
	defMop(name, function(mop, ctx)
		cg(ctx, function(f)
			f:load(ctx.objbase.r)
			f:i32(which)
			f:add()
			f:call(sget)
			f:refcast(R.vals)
		end)
		resolve(ctx, mop[1])
		cg(ctx, function(f)
			f:arrayget(vals)
		end)
	end)
end
defVecSlot('LoadConst', objframe.consts)
defVecSlot('LoadFree', objframe.frees)
-- Stack slot n, from base (params) or locbase (locals)
local function defStackSlot(lname, sname, basereg)
	defMop(lname, function(mop, ctx)
		cg(ctx, function(f)
			f:load(ctx[basereg].r)
		end)
		resolve(ctx, mop[1])
		cg(ctx, function(f)
			f:add()
			f:call(sget)
		end)
	end)
	defMop(sname, function(mop, ctx)
		cg(ctx, function(f)
			f:load(ctx[basereg].r)
		end)
		resolve(ctx, mop[1])
		cg(ctx, function(f)
			f:add()
		end)
		resolve(ctx, mop[2])
		cg(ctx, function(f)
			f:call(sset)
		end)
	end)
end
defStackSlot('LoadLocal', 'StoreLocal', 'locbase')
defStackSlot('LoadParam', 'StoreParam', 'base')
defMop('Truthy', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(_obj.truthy)
	end)
end)
defMop('Eq', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:eq()
	end)
end)
defMop('Lt', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	local isflt = isfloat(mop[1].out)
	cg(ctx, function(f)
		if isflt then
			f:lt()
		else
			f:lts()
		end
	end)
end)
defMop('Le', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	local isflt = isfloat(mop[1].out)
	cg(ctx, function(f)
		if isflt then
			f:le()
		else
			f:les()
		end
	end)
end)
defMop('Gt', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	local isflt = isfloat(mop[1].out)
	cg(ctx, function(f)
		if isflt then
			f:gt()
		else
			f:gts()
		end
	end)
end)
defMop('Ge', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	local isflt = isfloat(mop[1].out)
	cg(ctx, function(f)
		if isflt then
			f:ge()
		else
			f:ges()
		end
	end)
end)
local function binop(name, emit)
	defMop(name, function(mop, ctx)
		resolve(ctx, mop[1])
		resolve(ctx, mop[2])
		local isflt = isfloat(mop[1].out)
		cg(ctx, function(f)
			emit(f, isflt)
		end)
	end)
end
binop('Sub', function(f) f:sub() end)
defMop('Negate', function(mop, ctx)
	if isfloat(mop[1].out) then
		resolve(ctx, mop[1])
		cg(ctx, function(f)
			f:neg()
		end)
	else
		-- ints have no neg op: 0 - x
		cg(ctx, function(f)
			f:i64(0)
		end)
		resolve(ctx, mop[1])
		cg(ctx, function(f)
			f:sub()
		end)
	end
end)
binop('Mul', function(f) f:mul() end)
binop('Div', function(f, isflt)
	if isflt then
		f:div()
	else
		f:divs()
	end
end)
defMop('Add', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:add()
	end)
end)
defMop('BAnd', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:band()
	end)
end)
defMop('BOr', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:bor()
	end)
end)
defMop('BXor', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:xor()
	end)
end)
-- Lua's // and %: round toward minus infinity, so the remainder takes the divisor's sign
-- TODO int x//0 and x%0 trap in wasm, Lua raises an error. minint//-1 also traps
defMop('IDiv', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	if isfloat(mop[1].out) then
		cg(ctx, function(f)
			f:div()
			f:floor()
		end)
	else
		local ra, rb = newreg(ctx, 'i64'), newreg(ctx, 'i64')
		cg(ctx, function(f)
			f:store(rb.r)
			f:tee(ra.r)
			f:load(rb.r)
			f:divs()
			-- subtract 1 when there's a remainder & the signs differ
			f:load(ra.r)
			f:load(rb.r)
			f:rems()
			f:i64(0)
			f:ne()
			f:load(ra.r)
			f:load(rb.r)
			f:xor()
			f:i64(0)
			f:lts()
			f:band()
			f:i64extendu()
			f:sub()
		end)
	end
end)
defMop('Mod', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	if isfloat(mop[1].out) then
		-- a - floor(a/b)*b
		-- TODO differs from Lua's fmod based % when b is inf
		local ra, rb = newreg(ctx, 'f64'), newreg(ctx, 'f64')
		cg(ctx, function(f)
			f:store(rb.r)
			f:tee(ra.r)
			f:load(ra.r)
			f:load(rb.r)
			f:div()
			f:floor()
			f:load(rb.r)
			f:mul()
			f:sub()
		end)
	else
		local rb, rr = newreg(ctx, 'i64'), newreg(ctx, 'i64')
		cg(ctx, function(f)
			f:tee(rb.r)
			f:rems()
			f:tee(rr.r)
			-- add b when there's a remainder & its sign differs from b
			f:load(rb.r)
			f:i64(0)
			f:load(rr.r)
			f:i64(0)
			f:ne()
			f:load(rr.r)
			f:load(rb.r)
			f:xor()
			f:i64(0)
			f:lts()
			f:band()
			f:select()
			f:add()
		end)
	end
end)
defMop('Pow', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:call(rt.pow)
	end)
end)
-- Lua shifts are logical. Shifting 64 or more either way gives 0, a negative count shifts the other way
local shl64 = func(i64, i64, i64, function(f, a, n)
	f:load(n)
	f:i64(63)
	f:add()
	f:i64(126)
	f:gtu()
	f:iff(i64, function()
		f:i64(0)
	end, function()
		f:load(n)
		f:i64(0)
		f:ges()
		f:iff(i64, function()
			f:load(a)
			f:load(n)
			f:shl()
		end, function()
			f:load(a)
			f:i64(0)
			f:load(n)
			f:sub()
			f:shru()
		end)
	end)
end)
defMop('Shl', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:call(shl64)
	end)
end)
defMop('Shr', function(mop, ctx)
	resolve(ctx, mop[1])
	local rn = newreg(ctx, 'i64')
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:store(rn.r)
		f:i64(0)
		f:load(rn.r)
		f:sub()
		f:call(shl64)
	end)
end)
defMop('Str', function(mop, ctx)
	local s = assert(GS[mop[1]], 'Str: string missing from rt statics')
	cg(ctx, function(f)
		f:loadg(s)
	end)
end)
defMop('And', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:band()
	end)
end)
defMop('Or', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:bor()
	end)
end)
-- Resolve every arg, then call a wasm helper
local function callmop(name, helper)
	defMop(name, function(mop, ctx)
		for i=1,#mop do
			resolve(ctx, mop[i])
		end
		cg(ctx, function(f)
			f:call(helper)
		end)
	end)
end
callmop('ObjMetalessEq', _obj.eq)
callmop('MetaGet', frame.metaget)
callmop('BinMeta', frame.binmeta)
callmop('IdxWalk', frame.idxwalk)
callmop('NewIdxWalk', frame.newidxwalk)
callmop('StrConcat', _string.strconcat)
callmop('ToString', _string.numtostr)
callmop('MakeClosure', frame.makeclosure)
callmop('VargPushN', frame.loadvarg)
callmop('AppendN', frame.appendn)
callmop('AppendVarg', frame.appendvarg)
callmop('VargCount', frame.vargc)
defMop('IdxSelf', function(mop, ctx)
	cg(ctx, function(f)
		f:loadg(frame.idxself)
	end)
end)
defMop('VargPush', function(mop, ctx)
	cg(ctx, function(f)
		f:call(frame.pushvarg)
		f:drop()
	end)
end)
-- A frame helper left the pc to run next on the stack, -1 means the main function returned
local function switchframe(f, ctx, scopes)
	f:tee(ctx.pc.r)
	f:i32(0)
	f:lts()
	f:iff(function()
		f:i32(1)
		f:ret()
	end)
	f:br(scopes.nop)
end
-- Error(kind, operands...): call the prelude's errfn(kind, operands...), which raises the error.
-- Raises 'invalid operation' before errfn is set, or without a kind
defMop('Error', function(mop, ctx)
	cg(ctx, function(f, scopes)
		f:loadg(frame.errfn)
		f:refisnull()
		if mop[1] then
			f:iff(function()
				f:loadg(GS['invalid operation'])
				f:call(frame.throw)
				switchframe(f, ctx, scopes)
			end)
		else
			f:drop()
			f:loadg(GS['invalid operation'])
			f:call(frame.throw)
			switchframe(f, ctx, scopes)
		end
	end)
	if not mop[1] then
		return
	end
	cg(ctx, function(f)
		f:loadg(frame.errfn)
		f:call(tmppush)
		f:loadg(assert(GS[mop[1]], 'Error: kind missing from rt statics'))
		f:call(tmppush)
	end)
	for i=2,#mop do
		resolve(ctx, mop[i])
		cg(ctx, function(f)
			f:call(tmppush)
		end)
	end
	cg(ctx, function(f, scopes)
		f:i32(#mop)
		f:i32(calltypes.norm)
		f:i32(0)
		f:load(ctx.pc.r)
		f:i32(ctx.argoffset)
		f:add()
		f:call(frame.callmeta)
		switchframe(f, ctx, scopes)
	end)
end)
defMop('CallMeta', function(mop, ctx)
	for i=2,#mop do
		resolve(ctx, mop[i])
		cg(ctx, function(f)
			f:call(tmppush)
		end)
	end
	-- 'none' is a norm call that keeps no results
	local retc = mop[1] == 'none' and 0 or 1
	local callty = assert(calltypes[mop[1] == 'none' and 'norm' or mop[1]], 'CallMeta: unknown call type')
	cg(ctx, function(f, scopes)
		f:i32(#mop-2)
		f:i32(callty)
		f:i32(retc)
		f:load(ctx.pc.r)
		f:i32(ctx.argoffset)
		f:add()
		f:call(frame.callmeta)
		switchframe(f, ctx, scopes)
	end)
end)
defMop('CallChain', function(mop, ctx)
	local callty = assert(calltypes[mop[1]], 'CallChain: unknown call type')
	local helper = mop[2] and frame.callchainvarg or frame.callchain
	cg(ctx, function(f, scopes)
		f:load(ctx.bc.r)
		f:load(ctx.pc.r)
		f:i32(callty)
		f:call(helper)
		switchframe(f, ctx, scopes)
	end)
end)
defMop('Ret', function(mop, ctx)
	cg(ctx, function(f, scopes)
		f:call(frame.retframe)
		switchframe(f, ctx, scopes)
	end)
end)
defMop('If', function(mop, ctx)
	resolve(ctx, mop[1])
	local wty = microTypeToWasmType(mop.out)
	local t = genblock(ctx, mop.thenb, wty)
	local e = mop.elseb and genblock(ctx, mop.elseb, wty)
	cg(ctx, function(f, scopes)
		f:iff(wty,
			function()
				t(f, scopes)
			end,
			e and function()
				e(f, scopes)
			end
		)
	end)
end)
defMop('Select', function(mop, ctx)
	resolve(ctx, mop[1])
	local wty = microTypeToWasmType(mop.out)
	local t = thunk(ctx, function(subctx)
		resolve(subctx, mop[2])
	end)
	local e = thunk(ctx, function(subctx)
		resolve(subctx, mop[3])
	end)
	cg(ctx, function(f, scopes)
		f:iff(wty, function()
			t(f, scopes)
		end, function()
			e(f, scopes)
		end)
	end)
end)
defMop('Typeck', function(mop, ctx)
	local n = #mop
	local rs = {}
	for i=1,n do
		rs[i] = newreg(ctx, 'i32')
		resolve(ctx, mop[i])
		cg(ctx, function(f)
			f:call(typeof)
			f:store(rs[i].r)
		end)
	end
	local wty = microTypeToWasmType(mop.out)
	local cases = mop.cases
	local bodies = {}
	for i, case in ipairs(cases) do
		bodies[i] = genblock(ctx, case.block, wty)
	end
	local default = mop.default and genblock(ctx, mop.default, wty)
	cg(ctx, function(f, scopes)
		-- if case 1 then ... else if case 2 then ... else default
		local function rec(i)
			local case = cases[i]
			if not case then
				if default then
					default(f, scopes)
				end
				return
			end
			for j=1,n do
				f:load(rs[j].r)
				f:i32(case.tys[j])
				f:eq()
				if j > 1 then
					f:band()
				end
			end
			f:iff(wty, function()
				bodies[i](f, scopes)
			end, (cases[i+1] or default) and function()
				rec(i+1)
			end)
		end
		rec(1)
	end)
end)

-- Builtins written in wasm. Reads its own 1 byte arg: which builtin, numbered by rt/sys.lua
defMop('Syscall', function(mop, ctx)
	cg(ctx, function(f, scopes)
		-- required here: these modules require vm
		local std = require 'std'
		local stdcoro = require 'stdcoro'
		local stddebug = require 'stddebug'
		local stdmath = require 'stdmath'

		local function pushnil()
			lnil(f)
			f:call(tmppush)
		end

		-- Each builtin is a wasm func to call, a function that writes its code inline, or 'nyi' to trap.
		-- { sw = fn } is a builtin that may switch frames: fn gets the pc after the syscall
		-- & returns the pc to run next, the way call ops do
		local impl = {
			pcall = { sw = std.pcall },
			xpcall = { sw = std.xpcall },
			_fn_set_info = std.fn_set_info,
			_fn_info = std.fn_info,
			_frame = std.frame,
			_seterrfns = std.seterrfns,
			select = std.select,
			error = { sw = std.error },
			type = { sw = std.type },
			rawget = std.rawget,
			rawset = std.rawset,
			next = std.next,
			string_byte = std.string_byte,
			string_char = std.string_char,
			coro_status = stdcoro.coro_status,
			coro_running = stdcoro.coro_running,
			coro_create = stdcoro.coro_create,
			coro_resume = { sw = stdcoro.coro_resume },
			coro_yield = { sw = stdcoro.coro_yield },
			debug_getmetatable = stddebug.debug_getmetatable,
			debug_setmetatable = stddebug.debug_setmetatable,
			math_type = stdmath.math_type,
			math_abs = stdmath.math_abs,
			math_ceil = stdmath.math_ceil,
			math_floor = stdmath.math_floor,
			math_sin = stdmath.math_sin,
			math_cos = stdmath.math_cos,
			math_tan = stdmath.math_tan,
			math_asin = stdmath.math_asin,
			math_acos = stdmath.math_acos,
			math_exp = stdmath.math_exp,
			math_log = stdmath.math_log,
			math_atan = stdmath.math_atan,
			-- No files exist yet, so stdin/stdout are nil & io.type is always nil
			_stdin = pushnil,
			_stdout = pushnil,
			io_type = pushnil,
			_ioread = 'nyi',
			_iowrite = 'nyi',
			_ioflush = 'nyi',
			_ioclose = 'nyi',
			_iosetvbuf = 'nyi',
			_fn_set_localc = std.fn_set_localc,
			_fn_set_paramc = std.fn_set_paramc,
			_fn_set_isdotdotdot = std.fn_set_isdotdotdot,
			_fn_set_bc = std.fn_set_bc,
			_fn_set_frees = std.fn_set_frees,
			_fn_set_consts = std.fn_set_consts,
			_vec_new = std.vec_new,
			_fn_new = std.fn_new,
			_objid = std.objid,
			string_sub = std.string_sub,
			_reinterp = std.reinterp,
			_host = std.host,
			table_unpack = std.table_unpack,
			_lex = std.lexgen,
			_random = function()
				f:call(rt.random)
				f:call(alloc.newf64)
				f:call(tmppush)
			end,
		}

		local cases = {}
		for i, name in ipairs(require 'sys') do
			local body = assert(impl[name], 'Syscall has no impl: ' .. name)
			cases[#cases+1] = i-1
			cases[#cases+1] = function()
				if body == 'nyi' then
					f:unreachable()
				else
					if type(body) == 'function' then
						body()
					elseif type(body) == 'table' and rawget(body, 'sw') then
						f:load(ctx.pc.r)
						f:call(body.sw)
						switchframe(f, ctx, scopes)
					else
						f:call(body)
					end
					f:br(scopes.nop)
				end
			end
		end
		f:switch(function()
			f:load(ctx.bc.r)
			f:load(ctx.pc.r)
			f:arrayget(bytes, false)
			f:load(ctx.pc.r)
			f:i32(1)
			f:add()
			f:store(ctx.pc.r)
		end, table.unpack(cases))
		f:unreachable()
	end)
end)

local eval = func(i32, function(f)
	local base, objbase, locbase, pc = f:locals(i32, 4)
	local bc = f:locals(R.bytes)

	local L = {
		base = base, objbase = objbase, locbase = locbase, bc = bc, pc = pc,
	}
	local ctx = mkcgctx(f, L)

	-- Ops only branch to nop, so their order doesn't matter
	local switchparams = {}
	local oplist = {}
	for op in pairs(microbc.ops) do
		oplist[#oplist+1] = op
	end
	table.sort(oplist)
	for _, op in ipairs(oplist) do
		switchparams[#switchparams+1] = op
		switchparams[#switchparams+1] = genOp(ctx, op)
	end
	switchparams[#switchparams+1] = 'nop'
	local handled = {}
	for i=1,#switchparams,2 do
		handled[switchparams[i]] = true
	end
	for name, op in pairs(ops) do
		if not handled[op] then
			error('no handler for op ' .. name .. ': ' .. tostring(microbc.broken[op]))
		end
	end

	-- Registers microbc asked for during genOp
	for _, wty in ipairs(ctx.regtys) do
		local regdef = ctx.regdef[wty]
		local rs = table.pack(f:locals(wty, #regdef))
		for i=1,#regdef do
			regdef[i].r = rs[i]
		end
	end

	getf(f, 'base')
	f:tee(base)
	getf(f, 'locals')
	f:add()
	f:store(locbase)
	f:load(base)
	getf(f, 'frame')
	f:add()
	f:tee(objbase)
	f:call(sget)
	f:refcast(R.bytes)
	f:store(bc)
	getf(f, 'pc')
	f:store(pc)

	f:switch(function(scopes)
		-- switch bc[pc++]
		f:load(bc)
		f:load(pc)
		f:arrayget(bytes, false)
		f:load(pc)
		f:i32(1)
		f:add()
		f:store(pc)
	end, table.unpack(switchparams))

	-- for now we return to the host after each instruction
	setf(f, 'pc', function() f:load(pc) end)
	f:i32(0)
end)

return {
	objframe = objframe,
	calltypes = calltypes,
	init = init,
	eval = eval,
}

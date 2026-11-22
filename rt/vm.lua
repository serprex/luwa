local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, obj, num, str, vec, buf, tbl, functy, coro, allocsizef, nextid, newobj, newi64, newf64, newstrbuf, newvec, newvec1, newtbl =
	alloc.types, alloc.obj, alloc.num, alloc.str, alloc.vec, alloc.buf, alloc.tbl, alloc.functy, alloc.coro,
	alloc.allocsizef, alloc.nextid, alloc.newobj, alloc.newi64, alloc.newf64, alloc.newstrbuf, alloc.newvec, alloc.newvec1, alloc.newtbl

local _table = require '_table'
local tblget, tblset, tbllen = _table.tblget, _table.tblset, _table.tbllen

local stack = require 'stack'
local tmppush, tmppop, nthtmp, setnthtmp, extendtmp =
	stack.tmppush, stack.tmppop, stack.nthtmp, stack.setnthtmp, stack.extendtmp

local _string = require '_string'
local _obj = require 'obj'

local ops = require 'bc'

local util = require 'util'

local rt = require 'rt'
local microbc = require 'microbc'

local frame = require 'frame'
local dataframe, objframe, calltypes = frame.dataframe, frame.objframe, frame.calltypes

local init = func(i32, void, function(f, fn)
	-- Transition oluastack to having a stack frame from fn
	-- Assumes stack was previously setup

	local a, stsz, newstsz = f:locals(i32, 3)

	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.len)
	f:store(stsz)

	f:load(fn)
	f:call(tmppush)

	f:i32(dataframe.sizeof * 9)
	f:call(newstrbuf)
	f:tee(a)

	f:loadg(oluastack)
	f:load(a)
	f:i32store(coro.data)

	f:load(a)
	f:i32(dataframe.sizeof)
	f:i32store(buf.len)

	f:i32load(buf.ptr)
	f:tee(a)
	f:i32(calltypes.init)
	f:i32store8(dataframe.type)

	assert(dataframe.base == dataframe.pc + 4)
	f:load(a)
	f:i64(0)
	f:i64store(dataframe.pc)

	assert(dataframe.retb == dataframe.dotdotdot + 2)
	f:load(a)
	f:i32(4)
	f:i32store(dataframe.dotdotdot)

	f:load(a)
	f:i32(-1)
	f:i32store16(dataframe.retc)

	f:load(a)
	f:load(stsz)
	f:i32store16(dataframe.locals)

	f:load(a)
	f:load(stsz)
	f:i32(4)
	f:call(nthtmp)
	f:tee(fn)
	f:i32load(functy.localc)
	f:i32(2)
	f:shl()
	f:add()
	f:tee(newstsz)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.len)
	f:i32(4)
	f:sub()
	f:add()
	f:i32store16(dataframe.frame)

	f:load(newstsz)
	f:i32(objframe.sizeof)
	f:add()
	f:call(extendtmp)

	f:i32(4)
	f:store(fn)
	f:loop(function(loop)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(stsz)
		f:add()
		f:load(fn)
		f:add()
		f:i64(0)
		f:i64store(vec.base)

		f:load(fn)
		f:i32(8)
		f:add()
		f:tee(fn)
		f:load(newstsz)
		f:ltu()
		f:brif(loop)
	end)

	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.ptr)
	f:load(stsz)
	f:add()
	f:i32load(vec.base)
	f:tee(fn)

	f:call(tmppop)

	f:i32load(functy.bc)
	f:i32(objframe.tmpbc)
	f:call(setnthtmp)

	f:load(fn)
	f:i32load(functy.consts)
	f:i32(objframe.tmpconsts)
	f:call(setnthtmp)

	f:load(fn)
	f:i32load(functy.frees)
	f:i32(objframe.tmpfrees)
	f:call(setnthtmp)
end)

param0 = func(i32, function(f)
	f:call(loadframebase)
	f:i32load(dataframe.base)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.ptr)
	f:add()
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
	obj = i32,
	int = i32,
	float = i32,
	str = i32,
	tbl = i32,
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
	local rtbl = assert(ctx.regdef[wty], "Invalid register type")
	local n = ctx.regn[wty] + 1
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
		regdef = {
			[i32] = {},
			[i64] = {},
			[f32] = {},
			[f64] = {},
		},
		bc = { r = L.bc },
		pc = { r = L.pc },
		base = { r = L.base },
		objbase = { r = L.objbase },
		framebase = { r = L.framebase },
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
		regn = { [i32] = 0, [i64] = 0, [f32] = 0, [f64] = 0 },
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

-- Narrowing an object's type changes nothing in linear memory
defMop('As', function(mop, ctx)
	resolve(ctx, mop[1])
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
defMop('Load', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32load(mop[2] or 0)
	end)
end)
-- Boxes are vecs, value is at vec.base
defMop('Unbox', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32load(vec.base)
	end)
end)
defMop('SetBox', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:i32store(vec.base)
	end)
end)
defMop('Obj', function(mop, ctx)
	cg(ctx, function(f)
		f:i32(mop[1])
	end)
end)
defMop('Type', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32load8u(obj.type)
	end)
end)
defMop('IsTbl', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32load8u(obj.type)
		f:i32(types.tbl)
		f:eq()
	end)
end)
defMop('IsNumOrStr', function(mop, ctx)
	local r = newreg(ctx, 'i32')
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32load8u(obj.type)
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
		f:i64load(num.val)
	end)
end)
defMop('LoadFlt', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:f64load(num.val)
	end)
end)
defMop('LoadStrLen', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32load(str.len)
	end)
end)
defMop('Meta', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32load(tbl.meta)
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
		f:i32load(functy.paramc)
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
		f:call(newtbl)
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
		f:call(newvec1)
	end)
end)
defMop('IntObjFromInt', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i64extends()
		f:call(newi64)
	end)
end)
defMop('IntObjFromInt64', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(newi64)
	end)
end)
defMop('FltObjFromFlt', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(newf64)
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
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:call(util.popvec)
	end)
end)
defMop('Peek', function(mop, ctx)
	cg(ctx, function(f)
		f:i32(4)
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
		f:add()
		f:i32load(str.base + mop[1] * 4)
	end)
end)
-- Slot address helpers: each emits the address of slot 0, slots are 4 bytes apart
local function constbase(ctx, f)
	f:load(ctx.objbase.r)
	f:i32load(objframe.consts)
end
local function freebase(ctx, f)
	f:load(ctx.objbase.r)
	f:i32load(objframe.frees)
end
local function localbase(ctx, f)
	f:call(loadframebase)
	f:i32load(dataframe.base)
	f:call(loadframebase)
	f:i32load16u(dataframe.locals)
	f:add()
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.ptr)
	f:add()
end
local function parambase(ctx, f)
	f:call(param0)
end
-- Address of slot mop[1], from base
local function slotaddr(ctx, mop, base)
	cg(ctx, function(f)
		base(ctx, f)
	end)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32(4)
		f:mul()
		f:add()
	end)
end
local function defSlotLoad(name, base)
	defMop(name, function(mop, ctx)
		slotaddr(ctx, mop, base)
		cg(ctx, function(f)
			f:i32load(vec.base)
		end)
	end)
end
-- Address is computed before the value, fine while GC is off
local function defSlotStore(name, base)
	defMop(name, function(mop, ctx)
		slotaddr(ctx, mop, base)
		resolve(ctx, mop[2])
		cg(ctx, function(f)
			f:i32store(vec.base)
		end)
	end)
end
defSlotLoad('LoadConst', constbase)
defSlotLoad('LoadFree', freebase)
defSlotLoad('LoadLocal', localbase)
defSlotStore('StoreLocal', localbase)
defSlotLoad('LoadParam', parambase)
defSlotStore('StoreParam', parambase)
defMop('Truthy', function(mop, ctx)
	-- Could be a macroop
	resolve(ctx, mop[1])
	-- nil & false are the only values below TRUE
	cg(ctx, function(f)
		f:i32(TRUE)
		f:geu()
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
defMop('ToString', function(mop, ctx)
	-- TODO rt has no obj2str yet, prelude's tostring is written in Lua
	error('ToString: no obj2str in rt yet')
end)
defMop('Error', function(mop, ctx)
	cg(ctx, function(f)
		-- TODO stack unwinding etc
		f:unreachable()
	end)
end)
defMop('Str', function(mop, ctx)
	local s = assert(GS[mop[1]], 'Str: string missing from rt image')
	cg(ctx, function(f)
		f:i32(s)
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
callmop('StrConcat', frame.strconcat)
callmop('MakeClosure', frame.makeclosure)
callmop('VargPushN', frame.loadvarg)
callmop('AppendN', frame.appendn)
callmop('AppendVarg', frame.appendvarg)
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
defMop('CallMeta', function(mop, ctx)
	for i=2,#mop do
		resolve(ctx, mop[i])
		cg(ctx, function(f)
			f:call(tmppush)
		end)
	end
	local callty = assert(calltypes[mop[1]], 'CallMeta: unknown call type')
	cg(ctx, function(f, scopes)
		f:i32(#mop-2)
		f:i32(callty)
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
			f:i32load8u(obj.type)
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

		-- Store the 2nd param into field `field` of the function in the 1st param
		local function fnset(field, store, value)
			return function()
				f:call(param0)
				f:i32load(vec.base)
				f:call(param0)
				f:i32load(vec.base + 4)
				if value then value() end
				store(f, field)
			end
		end
		local function pushnil()
			f:i32(NIL)
			f:call(tmppush)
		end

		-- Each builtin is a wasm func to call, a function that writes its code inline, or 'nyi' to trap
		local impl = {
			pcall = std.pcall,
			select = std.select,
			error = std.error,
			type = std.type,
			rawget = std.rawget,
			rawset = std.rawset,
			next = std.next,
			string_byte = std.string_byte,
			string_char = std.string_char,
			coro_status = stdcoro.coro_status,
			coro_running = stdcoro.coro_running,
			coro_create = stdcoro.coro_create,
			coro_resume = stdcoro.coro_resume,
			coro_yield = stdcoro.coro_yield,
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
			_fn_set_isdotdotdot = fnset(functy.isdotdotdot, f.i32store8, function()
				-- truthy: not nil or false
				f:i32(TRUE)
				f:geu()
			end),
			_fn_set_bc = fnset(functy.bc, f.i32store),
			_fn_set_frees = fnset(functy.frees, f.i32store),
			_fn_set_consts = fnset(functy.consts, f.i32store),
			_vec_new = std.vec_new,
			_fn_new = std.fn_new,
			_lex = function()
				f:call(param0)
				f:i32load(vec.base)
				f:call(tmppush)
				f:call(require('_lex').lex)
			end,
			_random = function()
				f:call(rt.random)
				f:call(newf64)
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
			f:i32(1)
			f:add()
			f:tee(ctx.pc.r)
			f:add()
			f:i32load8u(str.base - 1)
		end, table.unpack(cases))
		f:unreachable()
	end)
end)

local function genLocals(f, wty, regdef)
	if #regdef > 0 then
		local rs = table.pack(f:locals(wty, #regdef))
		for i=1,#regdef do
			regdef[i].r = rs[i]
		end
	end
end
local eval = func(i32, function(f)
	local a, framebase, objbase, base, bc, pc = f:locals(i32, 6)

	local function loadframe()
		f:call(loadframebase)
		f:tee(framebase)
		f:i32load(dataframe.base)
		f:store(base)

		f:load(framebase)
		f:i32load(dataframe.pc)
		f:store(pc)
	end

	local L = {
		framebase = framebase, objbase = objbase, base = base, bc = bc, pc = pc,
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
	genLocals(f, i32, ctx.regdef[i32])
	genLocals(f, i64, ctx.regdef[i64])
	genLocals(f, f32, ctx.regdef[f32])
	genLocals(f, f64, ctx.regdef[f64])

	loadframe()

	f:switch(function(scopes)
		-- baseptr = ls.obj.ptr + base
		-- bc = baseptr.bc
		-- switch bc[pc++]
		f:call(loadframebase)
		f:tee(framebase)
		f:i32load16u(dataframe.frame)
		f:load(base)
		f:add()
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:add()
		f:tee(objbase)
		f:i32load(objframe.bc)
		f:tee(bc)
		f:load(pc)
		f:call(rt.echo)
		f:i32(1)
		f:add()
		f:tee(pc)
		f:add()
		f:i32load8u(str.base - 1)
		f:call(rt.echo)
	end, table.unpack(switchparams))

	-- check whether to yield (for now we'll yield after each instruction)
	f:loadg(oluastack)
	f:i32load(coro.data)
	f:tee(a)
	f:i32load(buf.ptr)
	f:load(a)
	f:i32load(buf.len)
	f:add()
	f:i32(dataframe.sizeof)
	f:sub()
	f:load(pc)
	f:i32store(dataframe.pc)

	f:i32(0)
end)

return {
	dataframe = dataframe,
	objframe = objframe,
	calltypes = calltypes,
	init = init,
	eval = eval,
}

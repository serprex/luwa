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
local vmlegacy = require 'vmlegacy'

local dataframe = {
	type = str.base + 0,
	pc = str.base + 1,
	base = str.base + 5, -- Base. params here
	dotdotdot = str.base + 9, -- base+dotdotdot = excess params here. Ends at base+locals
	retb = str.base + 11, -- base+retb = put return vals here
	retc = str.base + 13, -- base+retc = stack should be post return. 0xffff for piped return
	locals = str.base + 15, -- base+locals = locals here
	frame = str.base + 17, -- base+frame = objframe here
	sizeof = 19,
}
local objframe = {
	bc = vec.base + 0,
	consts = vec.base + 4,
	frees = vec.base + 8,
	tmpbc = 12,
	tmpconsts = 8,
	tmpfrees = 4,
	sizeof = 12,
}
local calltypes = {
	norm = 0, -- Reload locals
	init = 1, -- Return stack to coro src, src nil for main
	prot = 2, -- Reload locals
	call = 3, -- Continue call chain
	push = 4, -- Append intermediates to table
	bool = 5, -- Cast result to bool
}

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

loadframebase = func(i32, function(f)
	local a = f:locals(i32)
	f:loadg(oluastack)
	f:i32load(coro.data)
	f:tee(a)
	f:i32load(buf.ptr)
	f:load(a)
	f:i32load(buf.len)
	f:add()
	f:i32(dataframe.sizeof)
	f:sub()
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
-- A register is a table whose .r gets filled in with a wasm local by genLocals
local function newreg(ctx, mty)
	local wty = microTypeToWasmType(mty)
	local rtbl = assert(ctx.regdef[wty], "Invalid register type")
	local r = {}
	rtbl[#rtbl+1] = r
	return r
end
local resolve
local function resolvefirst(ctx, ast)
	local r = newreg(ctx, ast.out)
	ctx.temps[ast] = r
	mopcomp[ast.op](ast, ctx)
	return r
end
-- Evaluate for side effects, dropping any result
local function resolvevoid(ctx, ast)
	if ast.out then
		if not ctx.temps[ast] then
			resolve(ctx, ast)
			cg(ctx, function(f)
				f:drop()
			end)
		end
	else
		mopcomp[ast.op](ast, ctx)
	end
end
-- Evaluate, leaving result on wasm stack.
-- Nodes used more than once are kept in a register after their first evaluation
function resolve(ctx, ast)
	local wty = microTypeToWasmType(ast.out)
	if wty == void then
		return resolvevoid(ctx, ast)
	end
	-- TODO when mty == 'obj', track on tempstack
	local r = ctx.temps[ast]
	if r then
		cg(ctx, function(f)
			f:load(r.r)
		end)
		return
	end
	local reglife = assert(ctx.reglife[ast], 'AST node missing from liveness analysis')
	reglife.rcount = reglife.rcount + 1
	if reglife.usage == 1 then
		-- Only use, no need to juggle registers
		mopcomp[ast.op](ast, ctx)
	else
		r = resolvefirst(ctx, ast)
		cg(ctx, function(f)
			f:tee(r.r)
		end)
	end
end
-- Compile ast into separate code, for If/loop bodies
-- TODO a value first computed inside a branch is unset on the other path
local function resolvethunk(ctx, ast, void)
	local subctx = setmetatable({
		code = {},
	}, { __index = ctx })
	if void then
		resolvevoid(subctx, ast)
	else
		resolve(subctx, ast)
	end
	return function(f, scopes)
		for i=1,#subctx.code do
			subctx.code[i](f, scopes)
		end
	end
end
local function resolvereg(ctx, mop)
	local r = ctx.regs[mop]
	if not r then
		assert(mop.op == microbc.mops.Reg32)
		r = newreg(ctx, 'i32')
		ctx.regs[mop] = r
	end
	return r
end
-- Count how many times each node is used. Children are only counted
-- on a node's first visit, since the node itself is only evaluated once
local function initreglife(ctx, ast)
	local data = ctx.reglife[ast]
	if data then
		data.usage = data.usage + 1
		return
	end
	ctx.reglife[ast] = { usage = 1, rcount = 0 }
	local arg = ast.arg or {}
	for i=1,#ast do
		local child = ast[i]
		if type(child) == 'table' and arg[i] ~= 'r32' then
			initreglife(ctx, child)
		end
	end
end
-- Bytes of bytecode args read by an op, from its highest Arg index
local function argsize(ast, seen)
	if type(ast) ~= 'table' or seen[ast] then
		return 0
	end
	seen[ast] = true
	local n = 0
	if ast.op == microbc.mops.Arg then
		n = (ast[1] + 1) * 4
	end
	for i=1,#ast do
		n = math.max(n, argsize(ast[i], seen))
	end
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
	local opast = assert(microbc.ops[op], 'genOp: no microcode for op')
	local subctx = setmetatable({
		reglife = {},
		regs = {},
		temps = {},
		code = {},
	}, { __index = ctx })
	initreglife(subctx, opast)
	resolvevoid(subctx, opast)
	local argoffset = argsize(opast, {})
	-- TODO Phase 2: reserve spill slots on tmp stack, stackspace
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

defMop('Nop', function()
end)
defMop('Seq', function(mop, ctx)
	for i=1, #mop-1 do
		resolvevoid(ctx, mop[i])
	end
	resolve(ctx, mop[#mop])
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
-- Slots & boxes are vecs, values start at vec.base
defMop('LoadSlot', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32load(vec.base)
	end)
end)
defMop('Unbox', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32load(vec.base)
	end)
end)
defMop('StoreSlot', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:i32store(vec.base)
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
defMop('Reg32', function(mop, ctx)
	error('Reg32 is only used through LoadReg/StoreReg')
end)
defMop('StoreReg', function(mop, ctx)
	resolve(ctx, mop[2])
	local r = resolvereg(ctx, mop[1])
	cg(ctx, function(f)
		f:store(r.r)
	end)
end)
defMop('LoadReg', function(mop, ctx)
	local r = resolvereg(ctx, mop[1])
	cg(ctx, function(f)
		f:load(r.r)
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
defMop('Const', function(mop, ctx)
	cg(ctx, function(f)
		f:load(ctx.objbase.r)
		f:i32load(objframe.consts)
	end)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32(4)
		f:mul()
		f:add()
	end)
end)
defMop('Free', function(mop, ctx)
	cg(ctx, function(f)
		f:load(ctx.objbase.r)
		f:i32load(objframe.frees)
	end)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32(4)
		f:mul()
		f:add()
	end)
end)
defMop('Local', function(mop, ctx)
	cg(ctx, function(f)
		f:call(loadframebase)
		f:i32load(dataframe.base)
		f:call(loadframebase)
		f:i32load16u(dataframe.locals)
		f:add()
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:add()
	end)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32(4)
		f:mul()
		f:add()
	end)
end)
defMop('Param', function(mop, ctx)
	cg(ctx, function(f)
		f:call(param0)
	end)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i32(4)
		f:mul()
		f:add()
	end)
end)
defMop('VargLen', function(mop, ctx)
	cg(ctx, function(f)
		f:call(loadframebase)
		f:i32load16u(objframe.locals)
		f:call(loadframebase)
		f:i32load16u(dataframe.dotdotdot)
		f:sub()
		f:i32(2)
		f:shru()
	end)
end)
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
defMop('MemCpy4', function(mop, ctx)
	resolve(ctx, mop[1])

end)
defMop('If', function(mop, ctx)
	resolve(ctx, mop[1])
	local ifty = mop.out
	local wifty = microTypeToWasmType(ifty)
	assert(mop[3] or wifty == void)
	local isvoid = wifty == void
	local mop2 = resolvethunk(ctx, mop[2], isvoid)
	local mop3 = mop[3] and resolvethunk(ctx, mop[3], isvoid)
	cg(ctx, function(f, scopes)
		f:iff(wifty,
			function()
				mop2(f, scopes)
			end,
			mop3 and function()
				mop3(f, scopes)
			end
		)
	end)
end)
defMop('ForRange', function(mop, ctx)
	local r = resolvereg(ctx, mop[1])
	local rto = newreg(ctx, 'i32')
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:store(r.r)
	end)
	resolve(ctx, mop[3])
	local body = resolvethunk(ctx, mop[4])
	cg(ctx, function(f, scopes)
		f:store(rto.r)
		f:loop(function(loop)
			body(f, scopes)

			f:load(r.r)
			f:i32(1)
			f:add()
			f:tee(r.r)
			f:load(rto.r)
			f:ltu()
			f:brif(loop)
		end)
	end)
end)
defMop('Typeck', function(mop, ctx)
	local a1 = mop[1]
	local alen = #mop
	local hasDefault = (alen - 1) % (a1 + 1) == 0
	local rs = {}
	for i=1,a1 do
		rs[i] = newreg(ctx, 'i32')
		resolve(ctx, mop[i+1])
		cg(ctx, function(f)
			f:i32load8u(obj.type)
			f:store(rs[i].r)
		end)
	end
	-- Layout after the operands: groups of a1 type ids then a body, then an optional default body.
	-- i is where a group starts; when i == alen it's the default
	local wty = microTypeToWasmType(mop.out)
	local isvoid = wty == void
	local rthunks = {}
	for i=a1+2,alen,a1+1 do
		local body = i == alen and mop[i] or mop[i+a1]
		rthunks[i] = resolvethunk(ctx, body, isvoid)
	end
	cg(ctx, function(f, scopes)
		local function rec(i)
			if i < alen then
				return function()
					for j=1,a1 do
						f:load(rs[j].r)
						f:i32(mop[i+j-1])
						f:eq()
						if j > 1 then
							f:band()
						end
					end
					local nxt = rec(i+a1+1)
					f:iff(wty, function()
						rthunks[i](f, scopes)
					end, nxt)
				end
			elseif i == alen then
				return function()
					rthunks[i](f, scopes)
				end
			end
		end
		local top = rec(a1+2)
		if top then
			top()
		end
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
-- Ops compiled from microbc. Everything else uses vmlegacy's hand written handlers.
-- Grow this list one op at a time, checking the REPL still works after each
local microready = {
	[ops.LoadNil] = true,
	[ops.LoadFalse] = true,
	[ops.LoadTrue] = true,
	[ops.Pop] = true,
	[ops.Jmp] = true,
	[ops.Sub] = true,
	[ops.Mul] = true,
	[ops.Not] = true,
	[ops.Div] = true,
	[ops.IDiv] = true,
	[ops.Mod] = true,
	[ops.Pow] = true,
	[ops.BAnd] = true,
	[ops.BOr] = true,
	[ops.BXor] = true,
	[ops.Shl] = true,
	[ops.Shr] = true,
	[ops.CmpLe] = true,
	[ops.CmpLt] = true,
	[ops.CmpGe] = true,
	[ops.CmpGt] = true,
	[ops.Jif] = true,
	[ops.JifNot] = true,
	[ops.JifOrPop] = true,
	[ops.JifNotOrPop] = true,
	[ops.BNot] = true,
	[ops.LoadConst] = true,
	[ops.LoadLocal] = true,
	[ops.StoreLocal] = true,
	[ops.LoadParam] = true,
	[ops.StoreParam] = true,
	[ops.LoadFree] = true,
	[ops.LoadFreeBox] = true,
	[ops.StoreFreeBox] = true,
	[ops.LoadParamBox] = true,
	[ops.StoreParamBox] = true,
	[ops.LoadLocalBox] = true,
	[ops.StoreLocalBox] = true,
	[ops.Neg] = true,
	[ops.Add] = true,
	[ops.TblSet] = true,
	[ops.TblAdd] = true,
	[ops.TblNew] = true,
}
local eval = func(i32, function(f)
	local a, b, c, d, e,
		meta_callty, meta_retb, meta_retc, meta_key, meta_off,
		framebase, objbase, base, bc, pc = f:locals(i32, 5+5+5)
	local a64 = f:locals(i64, 1)

	local function loadframe()
		f:call(loadframebase)
		f:tee(framebase)
		f:i32load(dataframe.base)
		f:store(base)

		f:load(framebase)
		f:i32load(dataframe.pc)
		f:store(pc)
	end
	local function readArg()
		f:load(bc)
		f:load(pc)
		f:i32(4)
		f:add()
		f:tee(pc)
		f:add()
		f:i32load(str.base - 4)
	end
	local function readArg4()
		readArg()
		f:i32(2)
		f:shl()
	end

	local L = {
		a = a, b = b, c = c, d = d, e = e,
		meta_callty = meta_callty, meta_retb = meta_retb, meta_retc = meta_retc,
		meta_key = meta_key, meta_off = meta_off,
		framebase = framebase, objbase = objbase, base = base, bc = bc, pc = pc,
		a64 = a64,
		readArg = readArg, readArg4 = readArg4,
		dataframe = dataframe, objframe = objframe, calltypes = calltypes,
	}
	local ctx = mkcgctx(f, L)

	-- microbc ops only branch to nop, so they go first.
	-- Legacy keeps its order: a handler can only branch to labels after it
	local switchparams = {}
	local microops = {}
	for op in pairs(microready) do
		microops[#microops+1] = op
	end
	table.sort(microops)
	for _, op in ipairs(microops) do
		switchparams[#switchparams+1] = op
		switchparams[#switchparams+1] = genOp(ctx, op)
	end
	local arms = vmlegacy(f, L)
	for i=1,#arms,2 do
		assert(not microready[arms[i]], 'vmlegacy still has a handler for a microbc op')
		switchparams[#switchparams+1] = arms[i]
		switchparams[#switchparams+1] = arms[i+1]
	end
	switchparams[#switchparams+1] = 'nop'

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

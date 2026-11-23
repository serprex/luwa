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
local calltypes, getf, setf = frame.calltypes, frame.getf, frame.setf

-- Start running fn on the running coro, its args are what's on the stack.
-- The frame is type init, so returning from fn ends eval.
-- fn goes under the args at slot 0 like any frame's function, retb 0 marks it as main
local init = func(V, void, function(f, fnv)
	local n = f:locals(i32)
	f:i32(df.sizeof * 8)
	f:call(alloc.newframes)
	f:storeg(gframes)
	f:loadg(oluastack)
	f:loadg(gframes)
	f:structset(coro, 'data')
	f:call(stacklen)
	f:store(n)
	f:i32(1)
	f:call(extendtmp)
	f:i32(1)
	f:i32(0)
	f:load(n)
	f:call(_stack.scopy)
	f:i32(0)
	f:load(fnv)
	f:call(sset)
	f:i32(calltypes.init)
	f:i32(1)
	f:i32(frame.RETALL)
	f:call(frame.pushframe)
	setf(f, 'retb', function() f:i32(0) end)
	f:load(fnv)
	f:refcast(R.functy)
	f:call(frame.framefor)
end)

-- Small pieces of code that ops & helpers share
-- Return k when the i32 on the stack isn't 0
local function retif(f, k)
	f:iff(function()
		f:i32(k)
		f:ret()
	end)
end
-- Add k to the i32 on the stack
local function addk(f, k)
	if k ~= 0 then
		f:i32(k)
		f:add()
	end
end
-- The int or float in object v
local function intval(f, v)
	f:load(v)
	alloc.intvalst(f)
end
local function fltval(f, v)
	f:load(v)
	f:refcast(R.float)
	f:structget(float, 'val')
end
-- A field of the Lua stack
local function stackfield(f, name)
	f:loadg(gstack)
	f:structget(stack, name)
end
-- typeof(v) without the call
local function typeofv(f, v)
	f:load(v)
	alloc.typeofst(f)
end

-- Calls & jumps back to a function count towards compiling it. Past JITHOT the host is asked to.
-- Gives the function's JIT'd code, or null while it has none
local JITHOT = 500
local hotcode = func(R.functy, R.jitfty, function(f, fn)
	local cell = f:locals(R.jitcell)
	local code = f:locals(R.jitfty)
	local n = f:locals(i32)
	f:load(fn)
	f:structget(functy, 'jit')
	f:tee(cell)
	f:refisnull()
	f:iff(function()
		f:refnull(alloc.jitfty)
		f:ret()
	end)
	f:load(cell)
	f:structget(alloc.jitcell, 'code')
	f:tee(code)
	f:refisnull()
	f:eqz()
	f:iff(function()
		f:load(code)
		f:ret()
	end)
	f:load(cell)
	f:load(cell)
	f:structget(alloc.jitcell, 'hot')
	f:i32(1)
	f:add()
	f:tee(n)
	f:structset(alloc.jitcell, 'hot')
	f:load(n)
	f:i32(JITHOT)
	f:eq()
	f:iff(function()
		f:load(fn)
		f:call(rt.jitreq)
	end)
	f:refnull(alloc.jitfty)
end)

-- Go on to the next op. In the interpreter that's the end of eval's switch.
-- In JIT code it's a gap the JIT fills with a branch to the next op's code
local function brnop(f, ctx, scopes)
	if ctx.jit then
		f:gap{ kind = 'nop', inner = f.scope - ctx.jitroot }
		f:unreach()
		ctx.js.dead = true
	else
		f:br(scopes.nop)
	end
end

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
	-- an i31 or an int struct
	int = V,
	float = R.float,
	str = R.str,
	tbl = R.tbl,
	-- only for registers, microbc has no such type
	vals = R.vals,
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
		locbase = { r = L.locbase },
		consts = { r = L.consts },
		frees = { r = L.frees },
		fn = { r = L.fn },
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
		-- JIT code falls through to the next op, which sets pc itself
		if ctx.jit then
			return
		end
		-- SetPc branches out before this, so jumps skip it
		if argoffset > 0 then
			f:load(ctx.pc.r)
			addk(f, argoffset)
			f:store(ctx.pc.r)
		end
		f:br(scopes.nop)
	end
end

-- Most mops: put each arg on the wasm stack in order, then emit(f, mop, ctx, ...) adds the rest.
-- regs lists the microbc types of wasm locals emit needs, they come after ctx.
-- Args that aren't nodes (numbers, names) are left for emit to read from mop
local function defEmit(name, regs, emit)
	if not emit then
		regs, emit = {}, regs
	end
	defMop(name, function(mop, ctx)
		local rs = {}
		for i, ty in ipairs(regs) do
			rs[i] = newreg(ctx, ty)
		end
		for i=1,#mop do
			if type(mop[i]) == 'table' and mop[i].op then
				resolve(ctx, mop[i])
			end
		end
		cg(ctx, function(f)
			local ls = {}
			for i, r in ipairs(rs) do
				ls[i] = r.r
			end
			emit(f, mop, ctx, table.unpack(ls))
		end)
	end)
end
-- Call a wasm helper with the args
local function callmop(name, helper)
	defEmit(name, function(f)
		f:call(helper)
	end)
end
-- One instruction, fltop when the first arg is a float, else intop (or fltop when both are the same)
local function numop(name, fltop, intop)
	defEmit(name, function(f, mop)
		local op = isfloat(mop[1].out) and fltop or intop or fltop
		f[op](f)
	end)
end

-- Narrow an object's type: a cast, which can't fail where microbc uses it
defEmit('As', function(f, mop)
	local t = microTypeToWasmType(mop[2])
	if t ~= V then
		f:refcast(t)
	end
end)
defEmit('Int', function(f, mop) f:i32(mop[1]) end)
defEmit('Int64', function(f, mop) f:i64(mop[1]) end)
defEmit('Flt', function(f, mop) f:f32(mop[1]) end)
defEmit('Flt64', function(f, mop) f:f64(mop[1]) end)
defEmit('Unbox', function(f)
	f:refcast(R.box)
	f:structget(box, 'val')
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
defEmit('Obj', function(f, mop)
	assert(objconst[mop[1]], 'Obj: unknown constant')(f)
end)
callmop('Type', typeof)
defEmit('IsTbl', function(f)
	f:call(typeof)
	f:i32(types.tbl)
	f:eq()
end)
defEmit('IsTblOrVec', {'i32'}, function(f, mop, ctx, r)
	f:call(typeof)
	f:tee(r)
	f:i32(types.tbl)
	f:eq()
	f:load(r)
	f:i32(types.vec)
	f:eq()
	f:bor()
end)
defEmit('IsNumOrStr', {'i32'}, function(f, mop, ctx, r)
	f:call(typeof)
	f:tee(r)
	f:i32(types.float)
	f:leu()
	f:load(r)
	f:i32(types.str)
	f:eq()
	f:bor()
end)
defEmit('LoadInt', function(f) alloc.intvalst(f) end)
defEmit('LoadFlt', function(f) f:structget(float, 'val') end)
defEmit('LoadStrLen', function(f)
	f:structget(str, 'bytes')
	f:arraylen()
end)
defEmit('Meta', function(f) f:structget(tbl, 'meta') end)
callmop('LoadTblLen', tbllen)
callmop('StrCmp', _string.strcmp)
defEmit('LoadFuncParamc', function(f)
	f:refcast(R.functy)
	f:structget(functy, 'paramc')
end)
callmop('TblGet', tblget)
callmop('NewTbl', alloc.newtbl)
callmop('TblSet', tblset)
callmop('Box', alloc.newbox)
-- i31 when it fits, else box. Written out so the common case doesn't call
defEmit('IntObjFromInt', {'i32'}, function(f, mop, ctx, x)
	f:tee(x)
	f:i32(0x40000000)
	f:add()
	f:i32(0)
	f:ges()
	f:iff(V, function()
		f:load(x)
		f:refi31()
	end, function()
		f:load(x)
		f:i64extends()
		f:call(alloc.boxi64)
	end)
end)
defEmit('IntObjFromInt64', {'i64'}, function(f, mop, ctx, x)
	f:store(x)
	alloc.fitsi31(f, x)
	f:iff(V, function()
		f:load(x)
		f:i32wrap()
		f:refi31()
	end, function()
		f:load(x)
		f:call(alloc.boxi64)
	end)
end)
callmop('FltObjFromFlt', alloc.newf64)
defEmit('Flt64Int', function(f) f:i64truncs() end)
defEmit('Int64Flt', function(f) f:f64converts() end)
-- Push & Pop are written out here rather than calling tmppush & tmppop, the engine doesn't inline them into eval
-- In JIT code they're gaps, see jitpieces
defEmit('Push', {'obj', 'i32'}, function(f, mop, ctx, v, n)
	local js = ctx.js
	if js then
		f:gap{ kind = 'push', sp = js.sp }
		f:pop()
		js.sp = js.sp + 1
		js.top = math.max(js.top, js.sp)
		return
	end
	f:store(v)
	stackfield(f, 'len')
	f:tee(n)
	stackfield(f, 'arr')
	f:arraylen()
	f:geu()
	f:iff(function()
		f:i32(1)
		f:call(_stack.reserve)
	end)
	stackfield(f, 'arr')
	f:load(n)
	f:load(v)
	f:arrayset(vals)
	f:loadg(gstack)
	f:load(n)
	addk(f, 1)
	f:structset(stack, 'len')
end)
defEmit('Pop', {'i32', 'vals'}, function(f, mop, ctx, n, a)
	local js = ctx.js
	if js then
		f:gap{ kind = 'pop', sp = js.sp }
		f:push(V)
		js.sp = js.sp - 1
		js.low = math.min(js.low, js.sp)
		return
	end
	stackfield(f, 'arr')
	f:tee(a)
	stackfield(f, 'len')
	addk(f, -1)
	f:tee(n)
	f:arrayget(vals)
	-- slots past len are nil
	f:load(a)
	f:load(n)
	f:refnull(M.heap.eq)
	f:arrayset(vals)
	f:loadg(gstack)
	f:load(n)
	f:structset(stack, 'len')
end)
defEmit('Peek', function(f, mop, ctx)
	local js = ctx.js
	if js then
		f:gap{ kind = 'peek', sp = js.sp }
		f:push(V)
		js.low = math.min(js.low, js.sp - 1)
		return
	end
	f:i32(1)
	f:call(nthtmp)
end)
-- Where a SetPc goes, for the JIT: { 'arg', k } is the 4 byte arg k bytes past the opcode,
-- { 'pc', k } is k bytes past the opcode
local function jittarget(node)
	local m = microbc.mops
	if node.op == m.Arg then
		return { 'arg', node[1] * 4 }
	elseif node.op == m.ArgAt then
		return { 'arg', node[1] }
	elseif node.op == m.Add and node[1].op == m.Pc and node[2].op == m.Int then
		return { 'pc', node[2][1] }
	end
	error('SetPc: the JIT needs a target read from the bytecode')
end
defMop('SetPc', function(mop, ctx)
	if ctx.jit then
		-- the JIT makes this a branch to the target op
		local t = jittarget(mop[1])
		cg(ctx, function(f)
			f:gap{ kind = 'jmp', t[1], t[2], inner = f.scope - ctx.jitroot, sp = ctx.js.sp }
			f:unreach()
			ctx.js.dead = true
		end)
		return
	end
	local r = newreg(ctx, 'i32')
	resolve(ctx, mop[1])
	cg(ctx, function(f, scopes)
		f:tee(r.r)
		f:load(ctx.pc.r)
		f:ltu()
		f:iff(function()
			-- a jump back: go to the JIT'd code once there is some, it can start at any op
			f:load(ctx.fn.r)
			f:call(hotcode)
			f:refisnull()
			f:eqz()
			f:iff(function()
				setf(f, 'pc', function() f:load(r.r) end)
				f:br(ctx.reload)
			end)
		end)
		f:load(r.r)
		f:store(ctx.pc.r)
		f:br(scopes.nop)
	end)
end)
-- Arg n is the nth 4 byte arg after the opcode. pc already points past the opcode.
-- The JIT puts in the value from the bytecode
defEmit('Arg', function(f, mop, ctx)
	if ctx.jit then
		f:gap{ kind = 'arg', mop[1] * 4 }
		f:push(i32)
		return
	end
	f:load(ctx.bc.r)
	f:load(ctx.pc.r)
	addk(f, mop[1] * 4)
	f:call(frame.bcarg)
end)
defEmit('ArgAt', function(f, mop, ctx)
	if ctx.jit then
		f:gap{ kind = 'arg', mop[1] }
		f:push(i32)
		return
	end
	f:load(ctx.bc.r)
	f:load(ctx.pc.r)
	addk(f, mop[1])
	f:call(frame.bcarg)
end)
defEmit('Pc', function(f, mop, ctx)
	if ctx.jit then
		f:gap{ kind = 'pc' }
		f:push(i32)
		return
	end
	f:load(ctx.pc.r)
end)
-- Slot n of the function's consts or frees.
-- eval reads both from the frame's function when it changes frames
local function defVecSlot(name, which)
	defMop(name, function(mop, ctx)
		cg(ctx, function(f)
			f:load(ctx[which].r)
		end)
		resolve(ctx, mop[1])
		cg(ctx, function(f)
			f:arrayget(vals)
		end)
	end)
end
defVecSlot('LoadConst', 'consts')
defVecSlot('LoadFree', 'frees')
-- Stack slot n, from base (params) or locbase (locals)
local function defStackSlot(lname, sname, basereg)
	defEmit(lname, function(f, mop, ctx)
		f:load(ctx[basereg].r)
		f:add()
		f:call(sget)
	end)
	defMop(sname, function(mop, ctx)
		resolve(ctx, mop[1])
		cg(ctx, function(f)
			f:load(ctx[basereg].r)
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
-- Not nil & not false
defEmit('Truthy', {'obj'}, function(f, mop, ctx, v)
	f:tee(v)
	f:refisnull()
	f:load(v)
	alloc.lfalse(f)
	f:refeq()
	f:bor()
	f:eqz()
end)
numop('Eq', 'eq')
numop('Lt', 'lt', 'lts')
numop('Le', 'le', 'les')
numop('Gt', 'gt', 'gts')
numop('Ge', 'ge', 'ges')
numop('Add', 'add')
numop('Sub', 'sub')
numop('Mul', 'mul')
numop('Div', 'div', 'divs')
numop('BAnd', 'band')
numop('BOr', 'bor')
numop('BXor', 'xor')
numop('And', 'band')
numop('Or', 'bor')
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
-- Lua's // and %: round toward minus infinity, so the remainder takes the divisor's sign
-- TODO int x//0 and x%0 trap in wasm, Lua raises an error. minint//-1 also traps
defEmit('IDiv', {'i64', 'i64'}, function(f, mop, ctx, ra, rb)
	if isfloat(mop[1].out) then
		f:div()
		f:floor()
		return
	end
	f:store(rb)
	f:tee(ra)
	f:load(rb)
	f:divs()
	-- subtract 1 when there's a remainder & the signs differ
	f:load(ra)
	f:load(rb)
	f:rems()
	f:i64(0)
	f:ne()
	f:load(ra)
	f:load(rb)
	f:xor()
	f:i64(0)
	f:lts()
	f:band()
	f:i64extendu()
	f:sub()
end)
defEmit('Mod', {'i64', 'i64', 'f64', 'f64'}, function(f, mop, ctx, rb, rr, fa, fb)
	if isfloat(mop[1].out) then
		-- a - floor(a/b)*b
		-- TODO differs from Lua's fmod based % when b is inf
		f:store(fb)
		f:tee(fa)
		f:load(fa)
		f:load(fb)
		f:div()
		f:floor()
		f:load(fb)
		f:mul()
		f:sub()
		return
	end
	f:tee(rb)
	f:rems()
	f:tee(rr)
	-- add b when there's a remainder & its sign differs from b
	f:load(rb)
	f:i64(0)
	f:load(rr)
	f:i64(0)
	f:ne()
	f:load(rr)
	f:load(rb)
	f:xor()
	f:i64(0)
	f:lts()
	f:band()
	f:select()
	f:add()
end)
callmop('Pow', rt.pow)
-- Numeric for setup, like C Lua's forprep. Gives 0 to run the loop, 1 to skip it,
-- 2 when a value isn't a number or step is 0 (ForCoerce then deals with it).
-- Stores the loop's state in stack slots at, at+1 & at+2:
-- ints: init, the last value the loop reaches & step, so the loop never overflows.
-- floats (when init or step isn't an int): init, limit & step, all floats
local forprep = func(V, V, V, i32, i32, function(f, init, limit, step, at)
	local ti, tl, ts = f:locals(i32, 3)
	local i, l, s, n = f:locals(i64, 4)
	local fi, fl, fs = f:locals(f64, 3)
	-- stack slot at+k = what val leaves on the stack
	local function setslot(k, val)
		f:load(at)
		addk(f, k)
		val()
		f:call(sset)
	end
	-- s < 0 or s > 0
	local function stepcmp(cmp)
		f:load(s)
		f:i64(0)
		f[cmp](f)
	end
	f:load(init)
	f:call(typeof)
	f:tee(ti)
	f:load(limit)
	f:call(typeof)
	f:tee(tl)
	f:bor()
	f:load(step)
	f:call(typeof)
	f:tee(ts)
	f:bor()
	-- int is 0 & float is 1, anything else isn't a number
	f:i32(1)
	f:gtu()
	retif(f, 2)
	f:load(ti)
	f:load(ts)
	f:bor()
	f:eqz()
	f:iff(function()
		-- int loop
		intval(f, init)
		f:store(i)
		intval(f, step)
		f:tee(s)
		f:eqz()
		retif(f, 2)
		f:load(tl)
		f:iff(function()
			-- float limit: round towards the loop's start, clip to the int range
			fltval(f, limit)
			f:store(fl)
			stepcmp('lts')
			f:iff(f64, function()
				f:load(fl)
				f:ceil()
			end, function()
				f:load(fl)
				f:floor()
			end)
			f:tee(fl)
			f:f64(9223372036854775808.0)
			f:ge()
			f:iff(function()
				-- too big
				stepcmp('lts')
				retif(f, 1)
				f:i64(math.maxinteger)
				f:store(l)
			end, function()
				f:load(fl)
				f:f64(-9223372036854775808.0)
				f:lt()
				f:iff(function()
					-- too small
					stepcmp('gts')
					retif(f, 1)
					f:i64(math.mininteger)
					f:store(l)
				end, function()
					-- NaN skips the loop
					f:load(fl)
					f:load(fl)
					f:ne()
					retif(f, 1)
					f:load(fl)
					f:i64truncs()
					f:store(l)
				end)
			end)
		end, function()
			intval(f, limit)
			f:store(l)
		end)
		-- n = how many steps after the first, unsigned
		stepcmp('gts')
		f:iff(function()
			f:load(i)
			f:load(l)
			f:gts()
			retif(f, 1)
			f:load(l)
			f:load(i)
			f:sub()
			f:load(s)
			f:divu()
			f:store(n)
		end, function()
			f:load(i)
			f:load(l)
			f:lts()
			retif(f, 1)
			f:load(i)
			f:load(l)
			f:sub()
			-- -(s+1)+1 doesn't overflow for the smallest int
			f:i64(0)
			f:load(s)
			f:i64(1)
			f:add()
			f:sub()
			f:i64(1)
			f:add()
			f:divu()
			f:store(n)
		end)
		setslot(0, function()
			f:load(init)
		end)
		setslot(1, function()
			f:load(i)
			f:load(n)
			f:load(s)
			f:mul()
			f:add()
			f:call(alloc.newi64)
		end)
		setslot(2, function()
			f:load(step)
		end)
		f:i32(0)
		f:ret()
	end)
	-- float loop
	local function tof(v, t, out)
		f:load(t)
		f:iff(f64, function()
			fltval(f, v)
		end, function()
			intval(f, v)
			f:f64converts()
		end)
		f:store(out)
	end
	tof(init, ti, fi)
	tof(limit, tl, fl)
	tof(step, ts, fs)
	f:load(fs)
	f:f64(0)
	f:eq()
	retif(f, 2)
	-- runs when step <= 0 ? init >= limit : limit >= init, so NaN skips it
	f:f64(0)
	f:load(fs)
	f:ge()
	f:iff(i32, function()
		f:load(fi)
		f:load(fl)
		f:ge()
	end, function()
		f:load(fl)
		f:load(fi)
		f:ge()
	end)
	f:eqz()
	retif(f, 1)
	for k, v in ipairs({fi, fl, fs}) do
		setslot(k-1, function()
			f:load(v)
			f:call(alloc.newf64)
		end)
	end
	f:i32(0)
end)
defMop('ForPrep', function(mop, ctx)
	for i=2,4 do
		resolve(ctx, mop[i])
	end
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:load(ctx.locbase.r)
		f:add()
		f:call(forprep)
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
callmop('Shl', shl64)
defEmit('Shr', {'i64'}, function(f, mop, ctx, rn)
	f:store(rn)
	f:i64(0)
	f:load(rn)
	f:sub()
	f:call(shl64)
end)
defEmit('Str', function(f, mop)
	f:loadg(assert(GS[mop[1]], 'Str: string missing from rt statics'))
end)
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
defEmit('IdxSelf', function(f) f:loadg(frame.idxself) end)
defEmit('VargPush', function(f)
	f:call(frame.pushvarg)
	f:drop()
end)
-- A frame helper left the pc to run next on the stack, -1 means the main function returned.
-- The top frame may be a different one now: save pc in it & go back to where eval reads the frame
local function switchframe(f, ctx, scopes)
	f:tee(ctx.pc.r)
	f:i32(0)
	f:lts()
	retif(f, 1)
	setf(f, 'pc', function() f:load(ctx.pc.r) end)
	if ctx.jit then
		-- back to eval, which reads the frame again
		f:i32(0)
		f:ret()
		ctx.js.dead = true
	else
		f:br(ctx.reload)
	end
end
-- JIT code: before pushing onto the Lua stack, the values the JIT kept in locals go there first
local function jitflush(ctx)
	if ctx.jit then
		cg(ctx, function(f)
			f:gap{ kind = 'flush', sp = ctx.js.sp }
		end)
	end
end
-- Push mop's args from the ith on to the Lua stack
local function pushargs(ctx, mop, i)
	for j=i,#mop do
		resolve(ctx, mop[j])
		cg(ctx, function(f)
			f:call(tmppush)
		end)
	end
end
-- Push the prelude's errfn & the string naming the error kind
local function pusherrfn(ctx, kind)
	cg(ctx, function(f)
		f:loadg(frame.errfn)
		f:call(tmppush)
		f:loadg(assert(GS[kind], 'error kind missing from rt statics'))
		f:call(tmppush)
	end)
end
-- Call the function on the Lua stack under its argc args, keeping retc results.
-- It returns to pc + pcoff, a pc in this op's bytecode
local function callmeta(ctx, argc, callty, retc, pcoff)
	cg(ctx, function(f, scopes)
		f:i32(argc)
		f:i32(callty)
		f:i32(retc)
		f:load(ctx.pc.r)
		addk(f, pcoff)
		f:call(frame.callmeta)
		switchframe(f, ctx, scopes)
	end)
end
-- Error(kind, operands...): call the prelude's errfn(kind, operands...), which raises the error.
-- Raises 'invalid operation' before errfn is set, or without a kind
defMop('Error', function(mop, ctx)
	jitflush(ctx)
	cg(ctx, function(f, scopes)
		f:loadg(frame.errfn)
		f:refisnull()
		if mop[1] then
			f:iff(function()
				f:loadg(GS['invalid operation'])
				f:call(frame.throw)
				switchframe(f, ctx, scopes)
			end)
			-- only that branch left
			if ctx.js then
				ctx.js.dead = false
			end
		else
			f:drop()
			f:loadg(GS['invalid operation'])
			f:call(frame.throw)
			switchframe(f, ctx, scopes)
		end
	end)
	if mop[1] then
		pusherrfn(ctx, mop[1])
		pushargs(ctx, mop, 2)
		callmeta(ctx, #mop, calltypes.norm, 0, ctx.argoffset)
	end
end)
defMop('CallMeta', function(mop, ctx)
	jitflush(ctx)
	pushargs(ctx, mop, 2)
	-- 'none' is a norm call that keeps no results
	local retc = mop[1] == 'none' and 0 or 1
	local callty = assert(calltypes[mop[1] == 'none' and 'norm' or mop[1]], 'CallMeta: unknown call type')
	callmeta(ctx, #mop-2, callty, retc, ctx.argoffset)
end)
-- 3 results, then back to the start of this op
defMop('ForCoerce', function(mop, ctx)
	jitflush(ctx)
	pusherrfn(ctx, 'for')
	pushargs(ctx, mop, 1)
	callmeta(ctx, 4, calltypes.norm, 3, -1)
end)
defMop('CallChain', function(mop, ctx)
	local callty = assert(calltypes[mop[1]], 'CallChain: unknown call type')
	local helper
	if mop[3] then
		helper = mop[2] and frame.tailchainvarg or frame.tailchain
	else
		helper = mop[2] and frame.callchainvarg or frame.callchain
	end
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
-- JIT code: each branch of an If or Typeck starts from the stack use before it.
-- After, the stack use is that of the branches that didn't leave the op, which have to agree.
-- fallsthru is when there's no else & code can skip all the branches
local function jitbranches(ctx, fallsthru)
	local js = ctx.js
	if not js then
		return function(fn) return fn end, function() end
	end
	local sp0 = js.sp
	local live = {}
	if fallsthru then
		live[1] = sp0
	end
	local function wrap(fn)
		return fn and function()
			js.sp, js.dead = sp0, false
			fn()
			if not js.dead then
				live[#live+1] = js.sp
			end
		end
	end
	local function merge()
		for i = 2, #live do
			assert(live[i] == live[1], 'jit: branches leave the Lua stack at different heights')
		end
		js.sp, js.dead = live[1] or sp0, #live == 0
	end
	return wrap, merge
end
defMop('If', function(mop, ctx)
	resolve(ctx, mop[1])
	local wty = microTypeToWasmType(mop.out)
	local t = genblock(ctx, mop.thenb, wty)
	local e = mop.elseb and genblock(ctx, mop.elseb, wty)
	cg(ctx, function(f, scopes)
		local wrap, merge = jitbranches(ctx, not e)
		f:iff(wty,
			wrap(function()
				t(f, scopes)
			end),
			wrap(e and function()
				e(f, scopes)
			end)
		)
		merge()
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
		local v = newreg(ctx, 'obj')
		resolve(ctx, mop[i])
		cg(ctx, function(f)
			f:store(v.r)
			typeofv(f, v.r)
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
		local wrap, merge = jitbranches(ctx, not default)
		-- if case 1 then ... else if case 2 then ... else default
		local function rec(i)
			local case = cases[i]
			if not case then
				if default then
					wrap(function() default(f, scopes) end)()
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
			f:iff(wty, wrap(function()
				bodies[i](f, scopes)
			end), (cases[i+1] or default) and function()
				rec(i+1)
			end)
		end
		rec(1)
		merge()
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
		local stdstr = require 'stdstr'

		-- Each builtin is a wasm func to call, or a function that writes its code inline.
		-- { sw = fn } is a builtin that may switch frames: fn gets the pc after the syscall
		-- & returns the pc to run next, the way call ops do
		local impl = {
			pcall = { sw = std.pcall },
			xpcall = { sw = std.xpcall },
			_fn_set_info = std.fn_set_info,
			_fn_info = std.fn_info,
			_frame = std.frame,
			_seterrfns = std.seterrfns,
			select = { sw = std.select },
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
			_fn_set_localc = std.fn_set_localc,
			_fn_set_paramc = std.fn_set_paramc,
			_fn_set_isdotdotdot = std.fn_set_isdotdotdot,
			_fn_set_bc = std.fn_set_bc,
			_fn_set_frees = std.fn_set_frees,
			_fn_set_consts = std.fn_set_consts,
			_vec_new = std.vec_new,
			_fn_new = std.fn_new,
			_objid = std.objid,
			_upvalid = std.upvalid,
			_upval = std.upval,
			_fdepth = std.fdepth,
			_slot = std.slot,
			string_sub = std.string_sub,
			_reinterp = std.reinterp,
			_host = std.host,
			table_unpack = std.table_unpack,
			_lex = std.lexgen,
			_strmap = stdstr.strmap,
			_strrep = stdstr.strrep,
			_concat = stdstr.concat,
			_classend = stdstr.classend,
			_single = stdstr.single,
			_span = stdstr.span,
			_scan = stdstr.scan,
			_findplain = stdstr.findplain,
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
				if type(body) == 'function' then
					body()
				elseif type(body) == 'table' and rawget(body, 'sw') then
					f:load(ctx.pc.r)
					f:call(body.sw)
					switchframe(f, ctx, scopes)
				else
					f:call(body)
				end
				brnop(f, ctx, scopes)
			end
		end
		f:switch(function()
			f:load(ctx.bc.r)
			f:load(ctx.pc.r)
			f:arrayget(bytes, false)
			f:load(ctx.pc.r)
			addk(f, 1)
			f:store(ctx.pc.r)
			-- builtins may look at the frame's pc
			setf(f, 'pc', function() f:load(ctx.pc.r) end)
		end, table.unpack(cases))
		f:unreachable()
	end)
end)

local eval = func(i32, function(f)
	local base, locbase, pc, at = f:locals(i32, 4)
	local bc = f:locals(R.bytes)
	local consts, frees = f:locals(R.vals, 2)
	local farr = f:locals(R.i32s)
	local fn = f:locals(R.functy)

	local L = {
		base = base, locbase = locbase, bc = bc, pc = pc, consts = consts, frees = frees, fn = fn,
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

	-- Run up to this many ops before going back to the host, so it can do other work
	local budget = f:locals(i32)
	local code = f:locals(R.jitfty)
	local jr = f:locals(i32)
	f:i32(0x10000)
	f:store(budget)
	f:loop(function(reload)
		-- ops that switch frames come back here. Other ops leave the frame alone,
		-- so its fields stay in locals & pc is only saved in the frame when leaving
		ctx.reload = reload
		frame.ftop(f, farr, at)
		frame.frd(f, farr, at, 'base')
		f:tee(base)
		frame.frd(f, farr, at, 'locals')
		f:add()
		f:store(locbase)
		frame.frd(f, farr, at, 'pc')
		f:store(pc)
		-- the function is at base-1
		f:load(base)
		f:i32(1)
		f:sub()
		f:call(sget)
		f:refcast(R.functy)
		f:tee(fn)
		f:structget(functy, 'bc')
		f:store(bc)
		f:load(fn)
		f:structget(functy, 'consts')
		f:store(consts)
		f:load(fn)
		f:structget(functy, 'frees')
		f:store(frees)

		-- run the function's JIT'd code if it has some, else count towards making it
		f:load(fn)
		f:call(hotcode)
		f:tee(code)
		f:refisnull()
		f:eqz()
		f:iff(function()
			f:load(base)
			f:load(locbase)
			f:load(pc)
			f:load(bc)
			f:load(consts)
			f:load(frees)
			f:load(code)
			f:callref(alloc.jitfty)
			f:tee(jr)
			f:iff(function()
				-- main returned, or out of budget. pc is in the frame already
				f:load(jr)
				f:i32(1)
				f:eq()
				f:ret()
			end)
			-- it switched frames
			f:load(budget)
			f:i32(1)
			f:sub()
			f:tee(budget)
			f:brif(reload)
			f:i32(0)
			f:ret()
		end)

		f:loop(function(loop)
			f:switch(function(scopes)
				-- switch bc[pc++]
				f:load(bc)
				f:load(pc)
				f:arrayget(bytes, false)
				f:load(pc)
				addk(f, 1)
				f:store(pc)
			end, table.unpack(switchparams))

			f:load(budget)
			f:i32(1)
			f:sub()
			f:tee(budget)
			f:brif(loop)
		end)
	end)
	setf(f, 'pc', function() f:load(pc) end)
	f:i32(0)
end)

-- The JIT's pieces of code. Each op's microcode built like eval's,
-- in a function of the JIT module jm, which imports what it uses from rt.
-- The JIT function's params are base, locbase, pc, bc, consts & frees, the same as eval's locals.
-- Inside an op, pc is the pc after the opcode, like in eval
local function jitpieces(jm)
	local f = jm:builder({ i32, i32, i32, R.bytes, R.vals, R.vals }, { i32 })
	local ctx = {
		f = f,
		jit = true,
		regdef = {},
		regtys = {},
		base = { r = 1 },
		locbase = { r = 2 },
		pc = { r = 3 },
		bc = { r = 4 },
		consts = { r = 5 },
		frees = { r = 6 },
		-- how the op being emitted uses the Lua stack: sp is pushes less pops so far,
		-- low & top how far below & above where it started it got, dead once the code left the op
		js = {},
	}
	-- jumps back count this down, & leave when it reaches 0
	local budget = f:locals(i32)
	-- The JIT keeps the top of the Lua stack in these locals between ops, see jit.lua
	local NSLOT = 16
	local slots = table.pack(f:locals(V, NSLOT))
	for i = 2, NSLOT do
		assert(slots[i] == slots[1] + i - 1)
	end
	local oplist = {}
	for op in pairs(microbc.ops) do
		oplist[#oplist+1] = op
	end
	table.sort(oplist)
	local gens = {}
	for _, op in ipairs(oplist) do
		gens[op] = genOp(ctx, op)
	end
	for _, wty in ipairs(ctx.regtys) do
		local regdef = ctx.regdef[wty]
		local rs = table.pack(f:locals(wty, #regdef))
		for i=1,#regdef do
			regdef[i].r = rs[i]
		end
	end
	local function bytestr(t, i, j)
		local parts = {}
		for k = i, j, 4096 do
			parts[#parts+1] = string.char(table.unpack(t, k, math.min(k + 4095, j)))
		end
		return table.concat(parts)
	end
	-- The code fn emits as a string, & its gaps with pos made relative to it
	local js = ctx.js
	local function piece(fn)
		js.sp, js.low, js.top, js.dead = 0, 0, 0, false
		f:pushscope('block', {}, {})
		ctx.jitroot = f.scope
		local start = #f.bcode
		f.gaps = {}
		fn()
		f:popscope()
		for _, g in ipairs(f.gaps) do
			g.pos = g.pos - start
		end
		return { code = bytestr(f.bcode, start + 1, #f.bcode), gaps = f.gaps }
	end
	-- ops that use the Lua stack other than with Push, Pop & Peek, or leave the op for a call or return
	local m = microbc.mops
	local stackmops = { [m.CallChain] = true, [m.Ret] = true, [m.VargPush] = true, [m.VargPushN] = true,
		[m.AppendN] = true, [m.AppendVarg] = true, [m.Syscall] = true, [m.MakeClosure] = true }
	local pieces, oplen = {}, {}
	for _, op in ipairs(oplist) do
		local p = piece(function() gens[op]({}) end)
		pieces[op] = p
		-- pops it needs, most values above where it started, & change when it falls through to the next op
		p.need, p.top = -js.low, js.top
		p.fall = not js.dead and js.sp or nil
		p.slots = true
		microbc.walk(microbc.ops[op], function(node)
			if stackmops[node.op] then
				p.slots = false
			end
		end)
		-- bytes the op takes: call ops have a count of calls, Syscall a 1 byte arg
		local len = 1 + argsize(microbc.ops[op])
		microbc.walk(microbc.ops[op], function(node)
			if node.op == microbc.mops.CallChain then
				len = 'call'
			elseif node.op == microbc.mops.Syscall then
				len = 2
			end
		end)
		oplen[op] = len
	end
	local prologue = piece(function()
		f:i32(0x10000)
		f:store(budget)
	end)
	-- after a jump back has set pc: count budget down, at 0 save pc & leave
	local backedge = piece(function()
		f:load(budget)
		f:i32(1)
		f:sub()
		f:tee(budget)
		f:eqz()
		f:iff(function()
			setf(f, 'pc', function() f:load(ctx.pc.r) end)
			f:i32(2)
			f:ret()
		end)
	end)
	-- the code for a Push, Pop & Peek on the Lua stack itself
	local function snippet(fn)
		local start = #f.bcode
		fn()
		return bytestr(f.bcode, start + 1, #f.bcode)
	end
	local realpush = snippet(function()
		f:push(V)
		f:call(tmppush)
	end)
	local realpop = snippet(function()
		f:call(tmppop)
		f:pop()
	end)
	local realpeek = snippet(function()
		f:i32(1)
		f:call(nthtmp)
		f:pop()
	end)
	local locals = {}
	M.encode_varuint(locals, f.localbcn)
	for _, b in ipairs(f.localbc) do
		locals[#locals+1] = b
	end
	return {
		ops = pieces,
		oplen = oplen,
		prologue = prologue.code,
		backedge = backedge.code,
		locals = bytestr(locals, 1, #locals),
		-- 0 based local indices
		pclocal = ctx.pc.r - 1,
		slot0 = slots[1] - 1,
		nslot = NSLOT,
		realpush = realpush,
		realpop = realpop,
		realpeek = realpeek,
	}
end

return {
	calltypes = calltypes,
	init = init,
	eval = eval,
	jitpieces = jitpieces,
}

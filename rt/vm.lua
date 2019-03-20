local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, obj, num, str, vec, buf, tbl, functy, coro, allocsizef, nextid, newobj, newi64, newf64, newstrbuf, newvec, newvec1, newtbl =
	alloc.types, alloc.obj, alloc.num, alloc.str, alloc.vec, alloc.buf, alloc.tbl, alloc.functy, alloc.coro,
	alloc.allocsizef, alloc.nextid, alloc.newobj, alloc.newi64, alloc.newf64, alloc.newstrbuf, alloc.newvec, alloc.newvec1, alloc.newtbl

local _table = require '_table'
local tblget, tblset = _table.tblget, _table.tblset

local stack = require 'stack'
local tmppush, tmppop, nthtmp, setnthtmp, extendtmp =
	stack.tmppush, stack.tmppop, stack.nthtmp, stack.setnthtmp, stack.extendtmp

local _string = require '_string'
local _obj = require 'obj'

local ops = require 'bc'

local rt = require 'rt'
local microbc = require 'microbc'

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
local function defMop(opName, func)
	mopcomp[microbc.mops[opName]] = func
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
local function cg(ctx, fn)
	ctx.code[#ctx.code+1] = fn
end
local function newreg(ctx, mty)
	local wty = microTypeToWasmType(mty)
	local rtbl = ctx.regdef[wty]
	assert(rtbl, "Invalid register type")
	rtbl[#rtbl+1] = {}
end
local function resolvefirst(ctx, ast, wty)
	local r = newreg(ctx, ast.out)
	ctx.temps[ast] = r
	mopcomp[ast.op](ast, ctx)
	return r
end
local function resolvevoid(ctx, ast)
	if ast.out then
		local r = ctx.temps[ast]
		if not r then
			r = resolvefirst(ctx, ast)
			cg(ctx, function(f)
				f:store(r.r)
			end)
		end
	else
		mopcomp[ast.op](ast, ctx)
	end
end
local function resolve(ctx, ast)
	local mty = ast.out
	local wty = microTypeToWasmType(mty)
	if wty == void then
		return resolvevoid(ctx, ast)
	end
	-- TODO when mty == 'obj', track on tempstack
	local r = ctx.temps[ast]
	if r then
		cg(ctx, function(f)
			f:load(r.r)
		end)
	else
		resolvefirst(ctx, ast)
		cg(ctx, function(f)
			f:tee(r.r)
		end)
	end
end
local function resolvethunk(ctx, ast)
	local subctx = setmetatable({
		code = {},
	}, { __index = ctx })
	resolve(subctx, ast)
	return function(f, scopes)
		for i=1,#subctx.code do
			subctx.code[i](f, scopes)
		end
	end
end
local function resolvereg(ctx, mop)
	local r = ctx.regs[mop]
	if not r then
		assert(mop.op == microbc.mops.NewReg)
		r = newreg(ctx, 'i32')
		ctx.regs[mop] = r
	end
	return r
end
local function mkcgctx(f)
	bc = {}
	pc = {}
	base ={}
	objbase = {}
	framebase = {}
	return setmetatable({
		f = f,
		regdef = {
			i32 = {bc, pc, base, objbase, framebase},
			i64 = {},
			f32 = {},
			f64 = {},
		},
		bc = bc,
		pc = pc,
		base = base,
		objbase = objbase,
		framebase = framebase,
	}, ctxmt)
end

local function genOp(ctx, op)
	local subctx = setmetatable({
		regs = {},
		temps = {},
		code = {},
	}, ctx)
	resolvevoid(microbc.ops[op], subctx)
	return function(scopes)
		local f = ctx.f
		if stackspace > 0 then
			f:i32(stackspace)
			f:call(extendtmp)
		end
		emitOp(subctx, scopes, f)
		if argoffset > 0 then
			f:load(ctx.pc.r)
			f:i32(argoffset)
			f:add()
			f:store(ctx.pc.r)
		end
		f:br(scopes.exit)
	end
end

defMop('Nop', function()
end)
defMop('Seq', function(mop, ctx)
	for i=1, #mop-1 do
		resolvevoid(ctx, mop[i])
	end
	resolve(ctx, mop, #mop)
end)
defMop('Int', function(mop, ctx)
	cg(ctx, function(f)
		f:i32(mop[1])
	end)
end)
defMop('Int64', function(mop)
	cg(ctx, function(f)
		f:i64(mop[1])
	end)
end)
defMop('Flt', function(mop)
	cg(ctx, function(f)
		f:f32(mop[1])
	end)
end)
defMop('Flt64', function(mop)
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
defMop('NewReg', function(mop, ctx)
	error('Cannot resolve NewReg')
end)
defMop('StoreReg', function(mop, ctx)
	resolve(ctx, mop[2])
	local r = resolvereg(ctx, mop[1])
	cg(ctx, function(f)
		f:store(r.r)
	end)
end)
defMop('LoadReg', function(mop, ctx)
	cg(ctx, function(f)
		f:load(resolvereg(ctx, mop[1]))
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
		f:i64load(num.base)
	end)
end)
defMop('LoadFlt', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:f64load(num.base)
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
		f:i32load(tbl.len)
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
		f:extends()
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
defMop('FltInt64', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:i64converts()
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
defMop('Pop', function(mop)
	cg(ctx, function(f)
		f:call(tmppop)
	end)
end)
defMop('Arg', function(mop, ctx)
	cg(ctx, function(f)
		f:load(ctx.bc)
		f:load(ctx.pc)
		f:add()
		if mop[1] ~= 0 then
			f:i32(mop[1])
			f:i32(4)
			f:mul()
			f:add()
		end
		f:i32load(str.base)
	end)
end)
defMop('Const', function(mop, ctx)
	cg(ctx, function(f)
		f:load(ctx.objbase)
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
		f:load(ctx.objbase)
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
		f:i32load32u(dataframe.base)
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
	cg(ctx, function(f)
		f:i32(FALSE)
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
	cg(ctx, function(f)
		f:lts()
	end)
end)
defMop('Le', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:les()
	end)
end)
defMop('Gt', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:gts()
	end)
end)
defMop('Ge', function(mop, ctx)
	resolve(ctx, mop[1])
	resolve(ctx, mop[2])
	cg(ctx, function(f)
		f:ges()
	end)
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
defMop('ToString', function(mop, ctx)
	resolve(ctx, mop[1])
	cg(ctx, function(f)
		f:call(obj2str)
	end)
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
	local mop2 = resolvethunk(ctx, mop[2])
	local mop3 = mop[3] and resolvethunk(ctx, mop[3])
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
			f:br(loop)
		end)
	end)
end)

local function genLocals(wty, regdef)
	if #regdef > 0 then
		local rs = table.pack(f:locals(wty, #regdef))
		for i=1,#regdef do
			regdef[i].r = rs[i]
		end
	end
end
local eval = func(i32, function(f)
	local ctx = mkcgctx(f)

	local switchparams = {}
	for k,v in pairs(ops) do
		switchparams[#switchparams+1] = v
		switchparams[#switchparams+1] = genOp(ctx, v)
	end
	switchparams[#switchparams+1] = 'exit'

	genLocals(i32, ctx.regdef.i32)
	genLocals(i64, ctx.regdef.i64)
	genLocals(f32, ctx.regdef.f32)
	genLocals(f64, ctx.regdef.f64)
	local objbase = ctx.objbase.r
	local framebase = ctx.framebase.r
	local base = ctx.base.r
	local bc = ctx.bc.r
	local pc = ctx.pc.r

	local function loadframe()
		f:call(loadframebase)
		f:tee(framebase)
		f:i32load(dataframe.base)
		f:store(base)

		f:load(framebase)
		f:i32load(dataframe.pc)
		f:store(pc)
	end

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

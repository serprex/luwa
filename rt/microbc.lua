local alloc = require 'alloc'
local types = alloc.types
local mtypes = {}
local mops = {}
local mopmt = {}
function mopmt:__call(op)
	self.ops[#self.ops+1] = op
end

local function mkMop(op, sig)
	local id = #mops+1
	mops[id] = {
		op = op,
		sig = sig,
	}
	mops[op] = id
	return function(f, ...)
		return { op = id, ... }
	end
end
local function mkOp(op, f)
	ops[op] = f
end
local function mkType(name, obj)
	obj.name = name
	mtypes[name] = obj
	return obj
end
mkType('Lint', { type = 'const', ltype = 'number', mtype = 'integer' })
mkType('Lfloat', { type = 'const', ltype = 'number', mtype = 'float' })
mkType('Lstr', { type = 'const', ltype = 'string' })
mkType('Ltbl', { type = 'const', ltype = 'table' })
mkType('int', { type = 'obj', otype = types.int })
mkType('float', { type = 'obj', otype = types.float })
mkType('single', { type = 'obj', otype = types.single })
mkType('tbl', { type = 'obj', otype = types.tbl, layout = {
	arr = 'vec',
	hash = 'vec',
	meta = {'single', 'tbl'},
}})
mkType('str', { type = 'obj', otype = types.str })
mkType('vec', { type = 'obj', otype = types.vec })
mkType('buf', { type = 'obj', otype = types.buf, layout = {
	ptr = {'str', 'vec'},
}})
mkType('functy', { type = 'obj', otype = types.functy, layout = {
	bc = 'str',
	consts = {'single', 'vec'},
	frees = {'single', 'vec'},
}})
mkType('coro', { type = 'obj', otype = types.coro, layout = {
	caller = {'single', 'coro'},
	stack = 'buf',
	data = 'buf',
}})
mkType('i32', { type = 'i32' })
mkType('i64', { type = 'i64' })
mkType('f32', { type = 'f32' })
mkType('f64', { type = 'f64' })
local Nop = mkMop('Nop', {})
local Int = mkMop('Int', {
	arg = {'Lint'},
	out = {'i32'},
})
local ToString = mkMop('ToString', {
	alloc = true,
	arg = {'obj'},
	out = {'obj'},
})
local Int64 = mkMop('Int64', {
	arg = {'Lint'},
	out = {'i64'},
})
local Str = mkMop('Str', {
	arg = {'Lstr'},
	out = {'str'},
})
local Load = mkMop('Load', {
	arg = {'i32', 'Lint'},
	out = {'i32'},
})
local LoadInt = mkMop('LoadInt', {
	arg = {'obj'},
	out = {'i64'},
})
local LoadFlt = mkMop('LoadFlt', {
	arg = {'obj'},
	out = {'f64'},
})
local Free = mkMop('Free', {
	arg = {'i32'},
	out = {'obj'},
})
local Const = mkMop('Const', {
	arg = {'i32'},
	out = {'i32'},
})
local Local = mkMop('Local', {
	arg = {'i32'},
	out = {'i32'},
})
local Param = mkMop('Param', {
	arg = {'i32'},
	out = {'i32'},
})
local Store = mkMop('Store', {
	arg = { 'i32', 'i32' },
})
local Reg32 = mkMop('Reg32', {
	out = {'r32'},
})
local LoadReg = mkMop('LoadReg', {
	arg = { 'r32' },
	out = { 'i32' }
})
local StoreReg = mkMop('StoreReg', {
	arg = { 'r32', 'i32' }
})
local Eq = mkMop('Eq', {
	arg = { 'i32', 'i32' },
	out = { 'i32' }
})
local Add = mkMop('Add', {
	arg = {'i32', 'i32'},
	out = {'i32'},
})
local Or = mkMop('Or', {
	arg = {'i32', 'i32'},
	out = {'i32'},
})
local And = mkMop('And', {
	arg = {'i32', 'i32'},
	out = {'i32'},
})
local BNot64 = mkMop('BNot64', {
	arg = {'i64'},
	out = {'i64'},
})
local NegateInt = mkMop('NegateInt', {
	arg = {'obj'},
	out = {'obj'},
})
local NegateFloat = mkMop('NegateFloat', {
	arg = {'obj'},
	out = {'obj'},
})
local StrConcat = mkMop('StrConcat', {
	arg = {'obj','obj'},
	out = {'obj'},
})
-- TODO need to work out concept of 'deferred' block in arg sig
-- ie we're mixing up idea of input vs argument
local If = mkMop('If', function(args)
	local _then, _else = out(args[2]), args[3] and out(args[3])
	assert(tyeq(_then, _else), "If's branches with unequal type")
	arg = { 'i32', { type = 'block', out = _then } }
	if args[3] then
		arg[3] = { type = 'block', out = _else }
	end
	return {
		arg = arg,
		out = _then,
	}
end)
local ForRange = mkMop('ForRange', {
	arg = { 'r32', 'i32', 'i32', { type = 'block' } }
})
local Arg = mkMop('Arg', {
	arg = { 'Lint' },
	out = { 'i32' },
})
local Push = mkMop('Push', {
	arg = {'obj'},
	out = {},
})
local Pop = mkMop('Pop', {
	arg = {},
	out = {'obj'},
})
local Peek = mkMop('Peek', {
	arg = {},
	out = {'obj'},
})
local SetPc = mkMop('SetPc', {
	arg = {'i32'},
	out = {},
})
local Truthy = mkMop('Truthy', {
	arg = {'obj'},
	out = 'i32',
})
local Box = mkMop('Box', {
	alloc = true,
	arg = {'obj'},
	out = {'obj'},
})
local CloneFunc = mkMop('CloneFunc', {
	alloc = true,
	arg = {'obj'},
	out = {'obj'},
})
local ObjMetalessEq = mkMop('ObjMetalessEq', {
	arg = {'obj', 'obj'},
	out = {'i32'},
})
local IntObjFromInt = mkMop('IntObjFromInt', {
	alloc = true,
	arg = {'i32'},
	out = {'obj'},
})
local LoadStrLen = mkMop('LoadStrLen', {
	arg = {'obj'},
	out = {'i32'},
})
local Error = mkMop('Error', {
	alloc = true,
})
local Syscall = mkMop('Syscall', {
	alloc = true,
	arg = {'i32'},
	out = {},
})
local Int64Flt = mkMop('Int64Flt', {
	arg = {'i64'},
	out = {'f64'},
})
local FltInt64 = mkMop('Flt64Int', {
	arg = {'f64'},
	out = {'i64'},
})
local Meta = mkMop('Meta', {
	arg = {'obj'},
	out = {'obj'},
})
local Type = mkMop('Type', {
	arg = {'obj'},
	out = {'i32'},
})
local IsTbl = mkMop('IsTbl', {
	arg = {'obj'},
	out = {'i32'},
})
local IsNumOrStr = mkMop('IsNumOrStr', {
	arg = {'obj'},
	out = {'i32'},
})
local TblGet = mkMop('TblGet', {
	arg = {'obj', 'obj'},
	out = {'obj'},
})
local TblSet = mkMop('TblSet', {
	alloc = true,
	arg = {'obj', 'obj', 'obj'},
})
local LoadTblLen = mkMop('LoadTblLen', {
	arg = {'obj'},
	out = {'i32'},
})
local NewVec = mkMop('NewVec', {
	alloc = true,
	arg = {'i32'},
	out = {'obj'},
})
-- TODO CallMetaMethod
-- TODO CallBinMetaMethod
-- TODO FillRange
-- TODO MemCpy4
local VargLen = mkMop('VargLen', {
	arg = {},
	out = {'i32'},
})
-- TODO VargPtr
-- TODO AllocateTemp
-- TODO BoolCall
-- TODO Typeck
-- TODO LoadFuncParamc
-- TODO WriteDataFrame
-- TODO FillFromStack
local Parallel = Seq
local function Nil() return Int(0) end
local function False() return Int(4) end
local function True() return Int(8) end
local ops = {}
mkOp(bc.Nop, Nop())
mkOp(bc.LoadNil, Push(Nil()))
mkOp(bc.LoadFalse, Push(False()))
mkOp(bc.LoadTrue, Push(True()))
mkOp(bc.LoadParam, Push(Load(Param(Arg(0)))))
mkOp(bc.StoreParam, Store(Param(Arg(0)), Pop()))
mkOp(bc.LoadLocal, Push(Load(Local(Arg(0)))))
mkOp(bc.StoreLocal, Store(Local(Arg(0)), Pop()))
mkOp(bc.LoadFree, Push(Load(Free(Arg(0)))))
mkOp(bc.LoadFreeBox, Push(Load(Load(Free(Arg(0))))))
mkOp(bc.StoreFreeBox, Store(Load(Free(Arg(0))), Pop()))
mkOp(bc.LoadParamBox, Push(Load(Load(Param(Arg(0))))))
mkOp(bc.StoreParamBox, Store(Load(Param(Arg(0))), Pop()))
mkOp(bc.BoxParam, Store(Param(0), Box(Param(Arg(0)))))
mkOp(bc.BoxLocal, Store(Local(0), Box(Nil())))
mkOp(bc.LoadLocalBox, Push(Load(Load(Local(Arg(0)), vec.base))))
mkOp(bc.StoreLocalBox, Store(Load(Local(Arg(0)), vec.base), Pop()))
mkOp(bc.LoadConst, Push(Load(Const(Arg(0)), vec.base)))
mkOp(bc.Pop, Pop())
mkOp(bc.Syscall, Syscall(Arg(0)))
mkOp(bc.Jmp, SetPc(Arg(0)))
mkOp(bc.JifNot,
	If(
		Truthy(Pop()),
		SetPc(Arg(0))
	)
)
mkOp(bc.Jif,
	IfNot(
		Truthy(Pop()),
		SetPc(Arg(0))
	)
)
mkOp(bc.JifNotOrPop,
	If(
		Truthy(Peek()),
		SetPc(Arg(0)),
		Pop()
	)
)
mkOp(bc.JifOrPop,
	If(
		Truthy(Peek()),
		Pop(),
		SetPc(Arg(0))
	)
)
mkOp(bc.LoadFunc, (function()
	local func = CloneFunc(Const(Arg(1)))
	return Seq(
		If(
			Arg(0),
			Store(
				Add(func, Int(functy.frees)),
				FillFromStack(NewVec(Arg(0)), Arg(0))
			)
		),
		Push(func)
	)
end)())
mkOp(bc.LoadVarg, (function()
	-- TODO AllocateTemp points inside an object, needs special book keeping over allocation barriers
	local tmp = AllocateTemp(Arg(0))
	local vlen = VargLen()
	local vptr = VargPtr()
	return If(
		Lt(vlen, Arg(0)),
		function(f)
			local vlen4 = Mul(vlen, Int(4))
			return Parallel(
				MemCpy4(tmp, vptr, vlen4),
				FillRange(Add(tmp, vlen4), Nil(), Mul(Sub(Arg(0), vlen), Int(4)))
			)
		end,
		MemCpy4(tmp, vptr, Mul(Arg(0), Int(2)))
	)
end)())
mkOp(bc.AppendVarg, AppendRange(Pop(), VargPtr(), Arg(0)))
mkOp(bc.Call, (function()
	local nret = Arg(0)
	local baseframe = DataFrameTop()
	local rollingbase = Reg32()
	local ri = Reg32()
	local n0 = StoreReg(rollingbase, DataFrameTopBase())
	local n1 = AllocateDataFrames(Arg(1))
	-- TODO StoreName 'func'
	local n2 = ForRange(ri, Int(0), Arg(1), (function()
		local rival = LoadReg(ri)
		local newrollingbase = Add(LoadReg(rollingbase), Mul(LoadArg(rival), Int(4)))
		return Parallel(
			StoreReg(rollingbase, newrollingbase),
			WriteDataFrame(
				Add(baseframe, rival),
				If(rival, Int(3), Int(1)), -- type = i ? call : norm
				Int(0), -- pc
				newrollingbase, -- base
				Mul(LoadFuncParamc(func), Int(4)), -- dotdotdot
				Int(-4), -- retb
				Int(-1), -- retc
				0, --  TODO calc locals
				0 -- TODO calc frame
			)
		)
	end)())
	local n3 = PushObjFrameFromFunc(func)
	local n4 = SetPc(Int(0))
	return Seq(n0, n1, n2, n3, n4)
end)())
mkOp(bc.ReturnCall, Nop())
mkOp(bc.AppendCall, Nop())
mkOp(bc.ReturnCallVarg, Nop())
mkOp(bc.AppendCallVarg, Nop())

mkOp(bc.Not, Push(If(Truthy(Pop()), False(), True())))

mkOp(bc.Len, (function()
	local a = Pop()
	local aty = Type(a)
	return If(
		Eq(aty, Int(types.str)),
		Push(IntObjFromInt(LoadStrLen(a))),
		If(
			Eq(aty, Int(types.tbl)),
			(function()
				local ameta = Meta(a)
				If(ameta,
					function(f) CallMetaMethod('__len', ameta, a) end, -- TODO helper function this
					function(f) Push(IntObjFromInt(LoadTblLen(a))) end
				)
			end)(),
			Error()
		)
	)
end)())

mkOp(bc.Neg, (function()
	local a = Pop()
	return Typeck({a},
		{
			types.int,
			Push(NegateInt(a))
		}, {
			types.float,
			Push(NegateFloat(a))
		},
		{
			types.tbl,
			(function()
				local ameta = Meta(a)
				If(ameta,
					CallMetaMethod('__neg', ameta, a), -- TODO helper function this
					Error()
				)
			end)(),
		},
		Error()
	)
end)())

mkOp(bc.TblNew, Push(NewTbl()))
mkOp(bc.TblAdd, (function()
	local v = Pop()
	local k = Seq(v, Pop())
	local tbl = Seq(k, Pop())
	return Seq(TblSet(tbl, k, v), Pop(), Pop())
end)())

mkOp(bc.CmpEq, (function()
	local a = Pop()
	local b = Seq(a, Pop())
	return If(
		ObjMetalessEq(a, b),
		Push(True()),
		If(
			And(
				Eq(Type(a), Int(types.tbl)),
				Eq(Type(b), Int(types.tbl))
			),
			(function()
				local amt = Meta(a)
				local bmt = Meta(b)
				If(
					And(amt, bmt),
					(function()
						local amteq = TblGet(amt, Str('__eq'))
						local bmteq = TblGet(bmt, Str('__eq'))
						If(
							Eq(amteq, bmteq),
							-- TODO call as boolret
							BoolCall(amteq, a, b),
							-- CALL META
							Push(False())
						)
					end)(),
					Push(False())
				)
			end)(),
			Push(False())
		)
	)
end)())

function cmpop(op, cmpop, strlogic)
	mkOp(op, (function()
		local a = Pop()
		local b = Seq(a, Pop())
		return Typeck({a, b},
			{
				types.int,
				types.int,
				Push(If(
					cmpop(LoadInt(a), LoadInt(b)),
					True(), False()
				))
			},
			{
				types.float,
				types.float,
				Push(If(
					cmpop(LoadFlt(a), LoadFlt(b)),
					True(), False()
				))
			},
			{
				types.str,
				types.str,
				Push(If(
					cmpop(StrCmp(a, b), Int(0)),
					True(), False()
				))
			},
			{
				types.int,
				types.float,
				Push(If(
					cmpop(Int64Flt(LoadInt(a)), LoadFlt(b)),
					True(), False()
				))
			},
			{
				types.float,
				types.int,
				Push(If(
					cmpop(LoadFlt(a), Int64Flt(LoadInt(b))),
					True(), False()
				))
			},
			function(f)
				-- TODO metamethod fallbacks, error otherwise
			end
		)
	end)())
end
cmpop(bc.CmpLe, Le)
cmpop(bc.CmpLt, Lt)
cmpop(bc.CmpGe, Ge)
cmpop(bc.CmpGt, Gt)

function binmathop(op, floatlogic, intlogic, metamethod)
	mkOp(op, (function()
		local a = Pop()
		local b = Seq(a, Pop())
		return Typeck({a, b},
		{
			types.int,
			types.int,
			Push(intlogic(LoadInt(a), LoadInt(b)))
		},{
			types.float,
			types.float,
			Push(floatlogic(LoadFlt(a), LoadFlt(b)))
		},{
			types.int,
			types.float,
			Push(floatlogic(Int64Flt(LoadInt(a)), LoadFlt(b)))
		},{
			types.float,
			types.int,
			Push(floatlogic(LoadFlt(a), Int64Flt(LoadInt(b))))
		})
	end)())
end
function binmathop_mono(op, mop, metamethod)
	return binmathop(op, mop, mop, metamethod)
end
binmathop_mono(bc.Add, Add, '__add')
binmathop_mono(bc.Sub, Sub, '__sub')
binmathop_mono(bc.Mul, Mul, '__mul')
binmathop(bc.Div,
	function(a, b)
		return Div(Flt64Int(a), Flt64Int(b))
	end,
	function(a, b)
		return Div(a, b)
	end,
	'__div')
mkOp(bc.IDiv, (function()
	local a = Pop()
	local b = Seq(a, Pop())
	return Typeck({a, b},
	{
		types.int,
		types.int,
		function(f)
			Push(Div(LoadInt(a), LoadInt(b)))
		end
	},{
		types.float,
		types.float,
		function(f)
			Push(Div(Flt64Int(LoadFlt(a)), Flt64Int(LoadFlt(b))))
		end
	},{
		types.int,
		types.float,
		function(f)
			Push(Div(LoadInt(a), Flt64Int(LoadFlt(b))))
		end
	},{
		types.float,
		types.int,
		function(f)
			Push(Div(Flt64Int(LoadFlt(a)), LoadInt(b)))
		end
	})
end)())
binmathop(bc.Pow,
	function(f, a, b)
		return Pow(Flt64Int(a), Flt64Int(b))
	end,
	function(f, a, b)
		return Pow(a, b)
	end,
	'__pow')
binmathop_mono(bc.Mod, 'Mod', '__mod')
function binbitop(op, mop, metamethod)
	mkOp(op, (function()
		local a = Pop()
		local b = Seq(a, Pop())
		return Typeck({a, b},
		{
			types.int,
			types.int,
			Push(mop(LoadInt(a), LoadInt(b)))
			-- TODO assert floats are integer compatible
		},{
			types.float,
			types.float,
			Push(mop(Flt64Int(LoadFlt(a)), Flt64Int(LoadFlt(b))))
		},{
			types.int,
			types.float,
			Push(mop(LoadInt(a), Flt64Int(LoadFlt(b))))
		},{
			types.float,
			types.int,
			Push(mop(Flt64Int(LoadFlt(a)), LoadInt(b)))
		})
	end)())
end
binbitop(bc.BAnd, BAnd, '__band')
binbitop(bc.BOr, BOr, '__bor')
binbitop(bc.BXor, BXor, '__bxor')
binbitop(bc.Shr, Shr, '__shr')
binbitop(bc.Shl, Shl, '__shl')
mkOp(bc.BNot, (function()
	local a = Pop()
	return Typeck({a},
		{
			types.int,
			Push(BNot64(LoadInt(a)))
		},{
			types.float,
			Push(BNot64(Flt64Int(LoadFlt(a))))
		},
		CallMetaMethod('__bnot', a)
	)
end)())

mkOp(bc.Concat, (function()
	local b = Pop()
	local a = Seq(b, Pop())
	return Typeck({a, b},
		{
			types.str,
			types.str,
			Push(StrConcat(a, b))
		},
		If(
			And(IsNumOrStr(a), IsNumOrStr(b)),
			Push(StrConcat(ToString(a), ToString(b))),
			CallBinMetaMethod('__concat', a, b)
		)
	)
end)())

mkOp(bc.Idx, (function()
	local b = Pop()
	local a = Seq(b, Pop())
	local ameta = Meta(a)
	return If(ameta,
		CallMetaMethod('__index', a, b),
		If(IsTbl(a),
			TblGet(a, b),
			Error()
		)
	)
end)())

mkOp(bc.Append, (function()
	local b = Pop()
	local a = Seq(b, Pop())
	return TblSet(a, TblLen(a), b)
end)())

return {
	mops = mops,
	ops = ops,
}

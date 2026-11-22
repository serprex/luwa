require 'rt' -- sets NIL/FALSE/TRUE globals
local alloc = require 'alloc'
local types, vec, functy = alloc.types, alloc.vec, alloc.functy
local bc = require 'bc'
local mtypes = {}
local mops = {}
local ops = {}
-- ops whose microcode doesn't typecheck yet: op -> error message
local broken = {}

-- Result type of a node. Plain Lua values (atoms, nil) have no type
local function out(ast)
	if type(ast) ~= 'table' then
		return nil
	end
	return ast.out
end
-- Type errors are saved on the node instead of thrown,
-- so one unfinished op doesn't stop the whole file from loading
local function verify(mop)
	local arg = mop.arg
	if not arg then
		if #mop ~= 0 then
			mop.err = mop.err or (mops[mop.op] .. ': argless constructor received args')
		end
		return
	end
	for i=1,#arg do
		local a = arg[i]
		if a ~= 'atom' and out(mop[i]) ~= a then
			mop.err = mop.err or (mops[mop.op] .. ': arg ' .. i .. ' expected ' .. tostring(a) .. ' got ' .. tostring(out(mop[i])))
		end
	end
end
local function mkMop(op, sig)
	local id = #mops+1
	mops[id] = op
	mops[op] = id
	if type(sig) == 'table' then
		return function(...)
			local node = { op = id, ... }
			for k,v in pairs(sig) do
				node[k] = v
			end
			verify(node)
			return node
		end
	else
		return function(...)
			local node = { op = id, ... }
			local ok, meta = pcall(sig, node)
			if ok then
				for k,v in pairs(meta) do
					node[k] = v
				end
				verify(node)
			else
				node.err = op .. ': ' .. tostring(meta)
			end
			return node
		end
	end
end
-- First error found anywhere in an op's tree, or nil
local function findErr(ast, seen)
	if type(ast) == 'function' then
		return 'Lua function used where microcode expected'
	end
	if type(ast) ~= 'table' or seen[ast] then
		return nil
	end
	seen[ast] = true
	if not ast.op then
		return 'not a microcode node'
	end
	if ast.err then
		return ast.err
	end
	for i=1,#ast do
		local err = findErr(ast[i], seen)
		if err then
			return err
		end
	end
end
local function mkOp(op, f)
	assert(op, 'mkOp: unknown bytecode op')
	local err = findErr(f, {})
	if err then
		broken[op] = err
	else
		ops[op] = f
	end
end
local function GenericUnOp(args)
	assert(#args == 1, 'GenericUnOp: expects 1 param')
	local _a = out(args[1])
	return {
		arg = { _a },
		out = _a,
	}
end
local function GenericBinOp(args)
	assert(#args == 2, 'GenericBinOp: expects 2 params')
	local _a, _b = out(args[1]), out(args[2])
	assert(_a == _b, 'GenericBinOp: received mixed types')
	return {
		arg = { _a, _b },
		out = _a,
	}
end
local Nop = mkMop('Nop', {})
local Seq = mkMop('Seq', function(args)
	local arg = {}
	for i=1,#args-1 do
		arg[i] = out(args[i])
	end
	return {
		arg = arg,
		out = out(args[#args]),
	}
end)
local Void = mkMop('Void', function(args)
	assert(#args == 1, 'Void expects 1 param')
	return {
		arg = {out(args[1])}
	}
end)
local Int = mkMop('Int', {
	arg = {'atom'},
	out = 'i32',
})
local Int64 = mkMop('Int64', {
	arg = {'atom'},
	out = 'i64',
})
local Flt = mkMop('Flt', {
	arg = {'atom'},
	out = 'f32',
})
local Flt64 = mkMop('Flt64', {
	arg = {'atom'},
	out = 'f64',
})
-- A constant object pointer, like NIL/FALSE/TRUE
local Obj = mkMop('Obj', {
	arg = {'atom'},
	out = 'obj',
})
local Str = mkMop('Str', {
	arg = {'atom'},
	out = 'obj',
})
local ToString = mkMop('ToString', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
local Load = mkMop('Load', {
	arg = {'i32', 'atom'},
	out = 'i32',
})
local LoadInt = mkMop('LoadInt', {
	arg = {'obj'},
	out = 'i64',
})
local LoadFlt = mkMop('LoadFlt', {
	arg = {'obj'},
	out = 'f64',
})
local Free = mkMop('Free', {
	arg = {'i32'},
	out = 'obj',
})
local Const = mkMop('Const', {
	arg = {'i32'},
	out = 'i32',
})
local Local = mkMop('Local', {
	arg = {'i32'},
	out = 'i32',
})
local Param = mkMop('Param', {
	arg = {'i32'},
	out = 'i32',
})
local Store = mkMop('Store', {
	arg = { 'i32', 'i32' },
})
local Reg32 = mkMop('Reg32', {
	out = 'r32',
})
local LoadReg = mkMop('LoadReg', {
	arg = { 'r32' },
	out =  'i32' 
})
local StoreReg = mkMop('StoreReg', {
	arg = { 'r32', 'i32' }
})
-- Like GenericBinOp, but result is an i32 flag
local function GenericCmpOp(args)
	local sig = GenericBinOp(args)
	sig.out = 'i32'
	return sig
end
local Eq = mkMop('Eq', GenericCmpOp)
local Lt = mkMop('Lt', GenericCmpOp)
local Le = mkMop('Le', GenericCmpOp)
local Ge = mkMop('Ge', GenericCmpOp)
local Gt = mkMop('Gt', GenericCmpOp)
local Add = mkMop('Add', GenericBinOp)
local Sub = mkMop('Sub', GenericBinOp)
local Mul = mkMop('Mul', GenericBinOp)
local Div = mkMop('Div', GenericBinOp)
local BAnd = mkMop('BAnd', GenericBinOp)
local BOr = mkMop('BOr', GenericBinOp)
local BXor = mkMop('BXor', GenericBinOp)
local Negate = mkMop('Negate', GenericUnOp)
local Or = mkMop('Or', {
	arg = {'i32', 'i32'},
	out = 'i32',
})
local And = mkMop('And', {
	arg = {'i32', 'i32'},
	out = 'i32',
})
local NegateInt = mkMop('NegateInt', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
local NegateFloat = mkMop('NegateFloat', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
local StrConcat = mkMop('StrConcat', {
	alloc = true,
	arg = {'obj','obj'},
	out = 'obj',
})
-- TODO need to work out concept of 'deferred' block in arg sig
-- ie we're mixing up idea of input vs argument
-- If either branch has no result, the If has no result & any branch result is dropped
local If = mkMop('If', function(args)
	local _then, _else = out(args[2]), out(args[3])
	if _then ~= _else then
		assert(not args[3] or _then == nil or _else == nil, "If's branches with unequal type")
		_then, _else = nil, nil
	end
	return {
		arg = { 'i32' },
		out = _then,
	}
end)
local ForRange = mkMop('ForRange', {
	arg = { 'r32', 'i32', 'i32', nil }
})
local Arg = mkMop('Arg', {
	arg = { 'atom' },
	out =  'i32' ,
})
local Push = mkMop('Push', {
	arg = {'obj'},
})
local Pop = mkMop('Pop', {
	arg = {},
	out = 'obj',
})
local Peek = mkMop('Peek', {
	arg = {},
	out = 'obj',
})
local SetPc = mkMop('SetPc', {
	exit = true,
	arg = {'i32'},
})
local Truthy = mkMop('Truthy', {
	arg = {'obj'},
	out = 'i32',
})
local Box = mkMop('Box', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
local CloneFunc = mkMop('CloneFunc', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
local ObjMetalessEq = mkMop('ObjMetalessEq', {
	arg = {'obj', 'obj'},
	out = 'i32',
})
local IntObjFromInt = mkMop('IntObjFromInt', {
	alloc = true,
	arg = {'i32'},
	out = 'obj',
})
local IntObjFromInt64 = mkMop('IntObjFromInt64', {
	alloc = true,
	arg = {'i64'},
	out = 'obj',
})
local FltObjFromFlt = mkMop('FltObjFromFlt', {
	alloc = true,
	arg = {'f64'},
	out = 'obj',
})
local LoadStrLen = mkMop('LoadStrLen', {
	arg = {'obj'},
	out = 'i32',
})
local Error = mkMop('Error', {
	alloc = true,
})
local Syscall = mkMop('Syscall', {
	alloc = true,
	arg = {'i32'},
})
local Int64Flt = mkMop('Int64Flt', {
	arg = {'i64'},
	out = 'f64',
})
local Flt64Int = mkMop('Flt64Int', {
	arg = {'f64'},
	out = 'i64',
})
local Meta = mkMop('Meta', {
	arg = {'obj'},
	out = 'obj',
})
local Type = mkMop('Type', {
	arg = {'obj'},
	out = 'i32',
})
local IsTbl = mkMop('IsTbl', {
	arg = {'obj'},
	out = 'i32',
})
local IsNumOrStr = mkMop('IsNumOrStr', {
	arg = {'obj'},
	out = 'i32',
})
local TblGet = mkMop('TblGet', {
	arg = {'obj', 'obj'},
	out = 'obj',
})
local TblSet = mkMop('TblSet', {
	alloc = true,
	arg = {'obj', 'obj', 'obj'},
})
local LoadTblLen = mkMop('LoadTblLen', {
	arg = {'obj'},
	out = 'i32',
})
local LoadFuncParamc = mkMop('LoadFuncParamc', {
	arg = {'obj'},
	out = 'i32',
})
local NewVec = mkMop('NewVec', {
	alloc = true,
	arg = {'i32'},
	out = 'obj',
})
local function CallSignature(args)
	local arg = {}
	for i=1,#args do
		arg[i] = 'obj'
	end
	return { arg = arg }
end
local function CallMetaSignature(args)
	local arg = { 'atom' }
	for i=2,#args do
		arg[i] = 'obj'
	end
	return { arg = arg }
end
local CallMetaMethod = mkMop('CallMetaMethod', CallMetaSignature)
local CallBinMetaMethod = mkMop('CallBinMetaMethod', CallMetaSignature)
local CallBool = mkMop('CallBool', CallSignature)
local FillRange = mkMop('FillRange', {
	arg = {'i32', 'obj', 'i32'},
})
local MemCpy4 = mkMop('MemCpy4', {
	arg = {'i32', 'i32', 'i32'},
})
local VargLen = mkMop('VargLen', {
	arg = {},
	out = 'i32',
})
local VargPtr = mkMop('VargPtr', {
	arg = {},
	out = 'i32',
})
-- AllocateTemp's result should not live through an allocation barrier
local AllocateTemp = mkMop('AllocateTemp', {
	arg = {'i32'},
	out = 'i32',
})
-- TODO AllocateDataFrames
local Typeck = mkMop('Typeck', function(args)
	local a1 = args[1]
	local alen = #args
	assert(type(a1) == 'number' and a1>0, 'Typeck expects first param to be a positive number')
	local arg = {'atom'}
	for i=2,a1+1 do
		arg[i] = 'obj'
	end
	local hasDefault = (alen - 1) % (a1 + 1) == 0
	local out = out(args[#args])
	assert(hasDefault or not out, 'Typeck without default expects no out type')
	for i=a1+2,alen,a1+1 do
		arg[#arg+1] = out
		if i ~= alen then
			for j=0,a1-1 do
				assert(type(args[i+j]) == 'number', 'Typeck expects type ids')
			end
		end
	end
	return {
		arg = arg,
		out = out,
	}
end)
local WriteDataFrame = mkMop('WriteDataFrame', {
	arg = {
		'i32', -- temp offset
		'i32', -- type
		'i32', -- pc
		'i32', -- base
		'i32', -- dotdotdot
		'i32', -- retb
		'i32', -- retc
		'i32', -- locals
		'i32', -- frame
	}
})
local FillFromStack = mkMop('FillFromStack', {
	arg = {'obj', 'i32'},
})
-- Mops used by op sketches below. Signatures only, vm.lua doesn't compile these yet
local Mod = mkMop('Mod', GenericBinOp)
-- Lua's //: floors, int//int stays int
local IDiv = mkMop('IDiv', GenericBinOp)
local Pow = mkMop('Pow', GenericBinOp)
local Shl = mkMop('Shl', GenericBinOp)
local Shr = mkMop('Shr', GenericBinOp)
local StrCmp = mkMop('StrCmp', {
	arg = {'obj', 'obj'},
	out = 'i32',
})
local NewTbl = mkMop('NewTbl', {
	alloc = true,
	out = 'obj',
})
local AppendRange = mkMop('AppendRange', {
	alloc = true,
	arg = {'obj', 'i32', 'i32'},
})
-- Offset of the top dataframe in coro.data
local DataFrameTop = mkMop('DataFrameTop', {
	out = 'i32',
})
-- Base of the top dataframe
local DataFrameTopBase = mkMop('DataFrameTopBase', {
	out = 'i32',
})
local AllocateDataFrames = mkMop('AllocateDataFrames', {
	alloc = true,
	arg = {'i32'},
})
-- Like Arg, but the arg index is computed at runtime
local LoadArg = mkMop('LoadArg', {
	arg = {'i32'},
	out = 'i32',
})
local PushObjFrameFromFunc = mkMop('PushObjFrameFromFunc', {
	alloc = true,
	arg = {'obj'},
})
local function IfNot(c, t, e)
	return If(Eq(c, Int(0)), t, e)
end
-- Box an i64 or f64 into a number object
local function NumObj(x)
	if out(x) == 'f64' then
		return FltObjFromFlt(x)
	else
		return IntObjFromInt64(x)
	end
end
local function Nil() return Obj(NIL) end
local function False() return Obj(FALSE) end
local function True() return Obj(TRUE) end
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
mkOp(bc.Jif,
	If(
		Truthy(Pop()),
		SetPc(Arg(0))
	)
)
mkOp(bc.JifNot,
	IfNot(
		Truthy(Pop()),
		SetPc(Arg(0))
	)
)
mkOp(bc.JifOrPop,
	If(
		Truthy(Peek()),
		SetPc(Arg(0)),
		Pop()
	)
)
mkOp(bc.JifNotOrPop,
	If(
		Truthy(Peek()),
		Pop(),
		SetPc(Arg(0))
	)
)
mkOp(bc.LoadFunc, (function()
	local func = CloneFunc(Const(Arg(1)))
	return Seq(
		func,
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
	local tmp = AllocateTemp(Arg(0))
	local vlen = VargLen()
	local vptr = VargPtr()
	return Seq(vptr,
		If(
			Lt(vlen, Arg(0)),
			(function()
				local vlen4 = Mul(vlen, Int(4))
				return Seq(
					MemCpy4(tmp, vptr, vlen4),
					FillRange(Add(tmp, vlen4), Nil(), Mul(Sub(Arg(0), vlen), Int(4)))
				)
			end)(),
			MemCpy4(tmp, vptr, Mul(Arg(0), Int(4)))
		)
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
	local n2 = ForRange(ri, Int(0), Arg(1), (function()
		local rival = LoadReg(ri)
		local newrollingbase = Add(LoadReg(rollingbase), Mul(LoadArg(rival), Int(4)))
		return Seq(
			StoreReg(rollingbase, newrollingbase),
			WriteDataFrame(
				Add(baseframe, rival),
				If(rival, Int(3), Int(1)), -- type = i ? call : norm
				Int(0), -- pc
				newrollingbase, -- base
				Mul(LoadFuncParamc(func), Int(4)), -- dotdotdot
				Int(-4), -- retb
				If(rival, Int(-1), nret), -- retc
				0, --  TODO calc locals
				0 -- TODO calc frame
			)
		)
	end)())
	local n3 = PushObjFrameFromFunc(func)
	local n4 = SetPc(Int(0))
	return Seq(nret, n0, n1, n2, n3, n4)
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
				return If(ameta,
					CallMetaMethod('__len', ameta, a), -- TODO helper function this
					Push(IntObjFromInt(LoadTblLen(a)))
				)
			end)(),
			Error()
		)
	)
end)())

mkOp(bc.Neg, (function()
	local a = Pop()
	return Typeck(1, a,
		types.int,
		Push(IntObjFromInt64(Negate(LoadInt(a)))),
		types.float,
		Push(FltObjFromFlt(Negate(LoadFlt(a)))),
		types.tbl,
		(function()
			local ameta = Meta(a)
			return If(ameta,
				CallMetaMethod('__neg', ameta, a), -- TODO helper function this
				Error()
			)
		end)(),
		Error()
	)
end)())

mkOp(bc.TblNew, Push(NewTbl()))
mkOp(bc.TblAdd, (function()
	local v = Pop()
	local k = Seq(v, Pop())
	local tbl = Seq(k, Pop())
	return TblSet(tbl, k, v)
end)())
mkOp(bc.TblSet, (function()
	local k = Pop()
	local tbl = Seq(k, Pop())
	local v = Seq(tbl, Pop())
	return TblSet(tbl, k, v)
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
				return If(
					And(amt, bmt),
					(function()
						local amteq = TblGet(amt, Str('__eq'))
						local bmteq = TblGet(bmt, Str('__eq'))
						return If(
							Eq(amteq, bmteq),
							CallBool(amteq, a, b),
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

local function cmpop(op, cmpop, strlogic)
	mkOp(op, (function()
		local b = Pop() -- top of stack is right operand
		local a = Seq(b, Pop())
		return Typeck(2, a, b,
			types.int,
			types.int,
			Push(If(
				cmpop(LoadInt(a), LoadInt(b)),
				True(), False()
			)),
			types.float,
			types.float,
			Push(If(
				cmpop(LoadFlt(a), LoadFlt(b)),
				True(), False()
			)),
			types.str,
			types.str,
			Push(If(
				cmpop(StrCmp(a, b), Int(0)),
				True(), False()
			)),
			types.int,
			types.float,
			Push(If(
				cmpop(Int64Flt(LoadInt(a)), LoadFlt(b)),
				True(), False()
			)),
			types.float,
			types.int,
			Push(If(
				cmpop(LoadFlt(a), Int64Flt(LoadInt(b))),
				True(), False()
			)),
			-- TODO metamethod fallbacks
			Error()
		)
	end)())
end
cmpop(bc.CmpLe, Le)
cmpop(bc.CmpLt, Lt)
cmpop(bc.CmpGe, Ge)
cmpop(bc.CmpGt, Gt)

local function binmathop(op, floatlogic, intlogic, metamethod)
	mkOp(op, (function()
		local b = Pop() -- top of stack is right operand
		local a = Seq(b, Pop())
		return Typeck(2, a, b,
			types.int,
			types.int,
			Push(NumObj(intlogic(LoadInt(a), LoadInt(b)))),
			types.float,
			types.float,
			Push(NumObj(floatlogic(LoadFlt(a), LoadFlt(b)))),
			types.int,
			types.float,
			Push(NumObj(floatlogic(Int64Flt(LoadInt(a)), LoadFlt(b)))),
			types.float,
			types.int,
			Push(NumObj(floatlogic(LoadFlt(a), Int64Flt(LoadInt(b))))),
			-- TODO metamethod fallback
			Error()
		)
	end)())
end
local function binmathop_mono(op, mop, metamethod)
	return binmathop(op, mop, mop, metamethod)
end
binmathop_mono(bc.Add, Add, '__add')
binmathop_mono(bc.Sub, Sub, '__sub')
binmathop_mono(bc.Mul, Mul, '__mul')
binmathop(bc.Div,
	Div,
	function(a, b)
		return Div(Int64Flt(a), Int64Flt(b))
	end,
	'__div')
binmathop_mono(bc.IDiv, IDiv, '__idiv')
binmathop(bc.Pow,
	Pow,
	function(a, b)
		return Pow(Int64Flt(a), Int64Flt(b))
	end,
	'__pow')
binmathop_mono(bc.Mod, Mod, '__mod')
local function binbitop(op, mop, metamethod)
	mkOp(op, (function()
		local b = Pop() -- top of stack is right operand
		local a = Seq(b, Pop())
		-- TODO assert floats are integer compatible
		return Typeck(2, a, b,
			types.int,
			types.int,
			Push(NumObj(mop(LoadInt(a), LoadInt(b)))),
			types.float,
			types.float,
			Push(NumObj(mop(Flt64Int(LoadFlt(a)), Flt64Int(LoadFlt(b))))),
			types.int,
			types.float,
			Push(NumObj(mop(LoadInt(a), Flt64Int(LoadFlt(b))))),
			types.float,
			types.int,
			Push(NumObj(mop(Flt64Int(LoadFlt(a)), LoadInt(b)))),
			-- TODO metamethod fallback
			Error()
		)
	end)())
end
binbitop(bc.BAnd, BAnd, '__band')
binbitop(bc.BOr, BOr, '__bor')
binbitop(bc.BXor, BXor, '__bxor')
binbitop(bc.Shr, Shr, '__shr')
binbitop(bc.Shl, Shl, '__shl')
mkOp(bc.BNot, (function()
	local a = Pop()
	return Typeck(1, a,
		types.int,
		Push(NumObj(BXor(LoadInt(a), Int64(-1)))),
		types.float,
		Push(NumObj(BXor(Flt64Int(LoadFlt(a)), Int64(-1)))),
		CallMetaMethod('__bnot', Meta(a), a)
	)
end)())

mkOp(bc.Concat, (function()
	local b = Pop()
	local a = Seq(b, Pop())
	return Typeck(2, a, b,
		types.str,
		types.str,
		Push(StrConcat(a, b)),
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
		CallMetaMethod('__index', ameta, a, b),
		If(IsTbl(a),
			TblGet(a, b),
			Error()
		)
	)
end)())

mkOp(bc.Append, (function()
	local b = Pop()
	local a = Seq(b, Pop())
	return TblSet(a, IntObjFromInt(Add(LoadTblLen(a), Int(1))), b)
end)())

return {
	mops = mops,
	ops = ops,
	broken = broken,
}

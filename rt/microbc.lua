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
local Store = mkMop('Store', {
	arg = { 'i32', 'i32' },
})
-- Slots of the current function. Index comes first, value to store second
-- Local/Param live on the lua stack, Free/Const in the function's vecs
local LoadLocal = mkMop('LoadLocal', {
	arg = {'i32'},
	out = 'obj',
})
local StoreLocal = mkMop('StoreLocal', {
	arg = {'i32', 'obj'},
})
local LoadParam = mkMop('LoadParam', {
	arg = {'i32'},
	out = 'obj',
})
local StoreParam = mkMop('StoreParam', {
	arg = {'i32', 'obj'},
})
local LoadFree = mkMop('LoadFree', {
	arg = {'i32'},
	out = 'obj',
})
local LoadConst = mkMop('LoadConst', {
	arg = {'i32'},
	out = 'obj',
})
-- Value inside a box (a vec of length 1)
local Unbox = mkMop('Unbox', {
	arg = {'obj'},
	out = 'obj',
})
local SetBox = mkMop('SetBox', {
	arg = {'obj', 'obj'},
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
-- Builtin written in wasm, reads its own 1 byte arg
local Syscall = mkMop('Syscall', {
	alloc = true,
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
-- Mops used by op sketches below. Signatures only, vm.lua doesn't compile these yet
-- Metatable field, nil without a metatable. Strings use the string metatable
local MetaGet = mkMop('MetaGet', {
	arg = {'obj', 'obj'},
	out = 'obj',
})
-- Metamethod for a binary op: first operand's, else second's
local BinMeta = mkMop('BinMeta', {
	arg = {'obj', 'obj', 'obj'},
	out = 'obj',
})
-- a[b] following __index tables. If it ends at an __index function,
-- that's the result & IdxSelf is what to call it with, otherwise IdxSelf is 0
local IdxWalk = mkMop('IdxWalk', {
	arg = {'obj', 'obj'},
	out = 'obj',
})
local IdxSelf = mkMop('IdxSelf', {
	out = 'obj',
})
-- Call a function with some args, its 1 result is pushed when it returns.
-- First arg is the call type: 'norm', or 'bool' to make the result true/false.
-- Leaves the op, so it has to come last
local CallMeta = mkMop('CallMeta', function(args)
	local arg = { 'atom' }
	for i=2,#args do
		arg[i] = 'obj'
	end
	return { arg = arg, exit = true }
end)
-- Call op family, reads its own bytecode args. Args: call type, whether to pass varargs too
local CallChain = mkMop('CallChain', {
	exit = true,
	arg = {'atom', 'atom'},
})
-- Return everything after the frame's locals
local Ret = mkMop('Ret', {
	exit = true,
})
-- Push all varargs
local VargPush = mkMop('VargPush', {})
-- Push the first n varargs, nil filled
local VargPushN = mkMop('VargPushN', {
	arg = {'i32'},
})
-- Stack is table then n values: set them as t[1..n], leave the table
local AppendN = mkMop('AppendN', {
	alloc = true,
	arg = {'i32'},
})
-- Like AppendN, with varargs after the n values
local AppendVarg = mkMop('AppendVarg', {
	alloc = true,
	arg = {'i32'},
})
-- Copy of a function proto, the top n values are popped as its frees
local MakeClosure = mkMop('MakeClosure', {
	alloc = true,
	arg = {'obj', 'i32'},
	out = 'obj',
})
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
mkOp(bc.LoadParam, Push(LoadParam(Arg(0))))
mkOp(bc.StoreParam, StoreParam(Arg(0), Pop()))
mkOp(bc.LoadLocal, Push(LoadLocal(Arg(0))))
mkOp(bc.StoreLocal, StoreLocal(Arg(0), Pop()))
mkOp(bc.LoadFree, Push(LoadFree(Arg(0))))
mkOp(bc.LoadFreeBox, Push(Unbox(LoadFree(Arg(0)))))
mkOp(bc.StoreFreeBox, SetBox(LoadFree(Arg(0)), Pop()))
mkOp(bc.LoadParamBox, Push(Unbox(LoadParam(Arg(0)))))
mkOp(bc.StoreParamBox, SetBox(LoadParam(Arg(0)), Pop()))
mkOp(bc.BoxParam, StoreParam(Arg(0), Box(LoadParam(Arg(0)))))
mkOp(bc.BoxLocal, StoreLocal(Arg(0), Box(Nil())))
mkOp(bc.LoadLocalBox, Push(Unbox(LoadLocal(Arg(0)))))
mkOp(bc.StoreLocalBox, SetBox(LoadLocal(Arg(0)), Pop()))
mkOp(bc.LoadConst, Push(LoadConst(Arg(0))))
mkOp(bc.Pop, Pop())
mkOp(bc.Syscall, Syscall())
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
mkOp(bc.LoadFunc, Push(MakeClosure(LoadConst(Arg(1)), Arg(0))))
mkOp(bc.LoadVarg, VargPushN(Arg(0)))
mkOp(bc.AppendVarg, AppendVarg(Arg(0)))
mkOp(bc.Append, AppendN(Arg(0)))
mkOp(bc.Call, CallChain('norm', false))
mkOp(bc.CallVarg, CallChain('norm', true))
mkOp(bc.AppendCall, CallChain('push', false))
mkOp(bc.AppendCallVarg, CallChain('push', true))
mkOp(bc.Return, Ret())
mkOp(bc.ReturnVarg, Seq(VargPush(), Ret()))
-- No tail calls yet: bcgen emits Call keeping all results, then Return
mkOp(bc.ReturnCall, Error())
mkOp(bc.ReturnCallVarg, Error())

-- Call metamethod h with args if there is one, else raise an error
local function MetaOr(h, callty, ...)
	return If(Truthy(h), CallMeta(callty, h, ...), Error())
end
mkOp(bc.Not, Push(If(Truthy(Pop()), False(), True())))

mkOp(bc.Len, (function()
	local a = Pop()
	local aty = Type(a)
	return If(
		Eq(aty, Int(types.str)),
		Push(IntObjFromInt(LoadStrLen(a))),
		(function()
			local h = MetaGet(a, Str('__len'))
			return If(Truthy(h),
				CallMeta('norm', h, a),
				If(
					Eq(aty, Int(types.tbl)),
					Push(IntObjFromInt(LoadTblLen(a))),
					Error()
				)
			)
		end)()
	)
end)())

mkOp(bc.Neg, (function()
	local a = Pop()
	return Typeck(1, a,
		types.int,
		Push(IntObjFromInt64(Negate(LoadInt(a)))),
		types.float,
		Push(FltObjFromFlt(Negate(LoadFlt(a)))),
		MetaOr(MetaGet(a, Str('__unm')), 'norm', a, a)
	)
end)())

mkOp(bc.TblNew, Push(NewTbl()))
-- Table stays on the stack, constructors keep adding to it
mkOp(bc.TblAdd, (function()
	local v = Pop()
	local k = Seq(v, Pop())
	local tbl = Seq(k, Peek())
	return TblSet(tbl, k, v)
end)())
mkOp(bc.TblSet, (function()
	local k = Pop()
	local tbl = Seq(k, Pop())
	local v = Seq(tbl, Pop())
	return TblSet(tbl, k, v)
end)())

mkOp(bc.CmpEq, (function()
	local b = Pop() -- top of stack is right operand
	local a = Seq(b, Pop())
	return If(
		ObjMetalessEq(a, b),
		Push(True()),
		If(
			And(IsTbl(a), IsTbl(b)),
			(function()
				local h = BinMeta(a, b, Str('__eq'))
				return If(Truthy(h),
					CallMeta('bool', h, a, b),
					Push(False())
				)
			end)(),
			Push(False())
		)
	)
end)())

local function cmpop(op, cmpop, metamethod, swap)
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
			swap
				and MetaOr(BinMeta(b, a, Str(metamethod)), 'bool', b, a)
				or MetaOr(BinMeta(a, b, Str(metamethod)), 'bool', a, b)
		)
	end)())
end
cmpop(bc.CmpLe, Le, '__le')
cmpop(bc.CmpLt, Lt, '__lt')
cmpop(bc.CmpGe, Ge, '__le', true)
cmpop(bc.CmpGt, Gt, '__lt', true)

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
			MetaOr(BinMeta(a, b, Str(metamethod)), 'norm', a, b)
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
			MetaOr(BinMeta(a, b, Str(metamethod)), 'norm', a, b)
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
		MetaOr(MetaGet(a, Str('__bnot')), 'norm', a, a)
	)
end)())

mkOp(bc.Concat, (function()
	local b = Pop()
	local a = Seq(b, Pop())
	return Typeck(2, a, b,
		types.str,
		types.str,
		Push(StrConcat(a, b)),
		-- TODO numbers: rt has no number to string yet
		MetaOr(BinMeta(a, b, Str('__concat')), 'norm', a, b)
	)
end)())

mkOp(bc.Idx, (function()
	local b = Pop()
	local a = Seq(b, Pop())
	local v = IdxWalk(a, b)
	local recv = IdxSelf()
	return Seq(v, If(Truthy(recv),
		CallMeta('norm', v, recv, b),
		Push(v)
	))
end)())

return {
	mops = mops,
	ops = ops,
	broken = broken,
}

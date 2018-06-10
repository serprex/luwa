local bc = require 'bc'
local alloc = require 'alloc'
local types = alloc.types
local mops = {}
local function mkMop(op)
	local id = #mops+1
	mops[id] = op
	mops[op] = id
	return function(...)
		return { op = op, id = id, ... }
	end
end
local Nop = mkMop('Nop')
local Int = mkMop('Int')
local Load = mkMop('Load')
local Store = mkMop('Store')
local StoreName = mkMop('StoreName')
local StoreNameInt = mkMop('StoreNameInt')
local LoadName = mkMop('LoadName')
local Eq = mkMop('Eq')
local If = mkMop('If')
local In = mkMop('In')
local Arg = mkMop('Arg')
local Push = mkMop('Push')
local Truthy = mkMop('Truthy')
local CloneFunc = mkMop('CloneFunc')
local ObjMetalessEq = mkMop('ObjMetalessEq')
local NopAtom = Nop()
local NilAtom = Int(0)
local FalseAtom = Int(4)
local TrueAtom = Int(8)
local ops = {}
ops[bc.Nop] = NopAtom
ops[bc.LoadNil] = Push(NilAtom)
ops[bc.LoadFalse] = Push(FalseAtom)
ops[bc.LoadTrue] = Push(TrueAtom)
ops[bc.LoadParam] = Push(Load(Param(Arg(0))))
ops[bc.StoreParam] = Store(Param(Arg(0)), Pop())
ops[bc.LoadLocal] = Push(Load(Local(Arg(0))))
ops[bc.StoreLocal] = Store(Local(Arg(0)), Pop())
ops[bc.LoadFree] = Push(Load(Free(Arg(0))))
ops[bc.LoadFreeBox] = Push(Load(Load(Free(Arg(0)))))
ops[bc.StoreFreeBox] = Store(Load(Free(Arg(0))), Pop())
ops[bc.LoadParamBox] = Push(Load(Load(Param(Arg(0)))))
ops[bc.StoreParamBox] = Store(Load(Param(Arg(0))), Pop())
ops[bc.BoxParam] = Store(Param(0), Box(Param(Arg(0))))
ops[bc.BoxLocal] = Store(Local(0), Box(NilAtom))
ops[bc.LoadLocalBox] = Push(Load(Load(Local(Arg(0)))))
ops[bc.StoreLocalBox] = Store(Load(Local(Arg(0))), Pop())
ops[bc.LoadConst] = Push(Load(Const(Arg(0))))
ops[bc.Pop] = Pop()
ops[bc.Syscall] = Syscall(Arg(0))
ops[bc.Jmp] = SetPc(Arg(0))
ops[bc.JifNot] = If(
	Truthy(Pop()),
	SetPc(Arg(0)),
	Nop()
)
ops[bc.Jif] = If(
	Truthy(Pop()),
	Nop(),
	SetPc(Arg(0))
)
ops[bc.LoadFunc] = Seq(
	StoreName('func', CloneFunc(Const(Arg(1)))),
	If(
		Arg(0),
		Store(Add(LoadName('func'), functy.frees), FillFromStack(NewVec(Arg(0)), Arg(0))),
		Nop()
	),
	Push(LoadName('func'))
)

-- TODO
ops[bc.AppendVarg] = {}
-- TODO
ops[bc.Call] = Seq(
	StoreNameInt('nret', Arg(0)),
	StoreNameInt('baseframe', DataFrameTop()),
	StoreNameInt('rollingbase', DataFrameTopBase()),
	AllocateDataFrames(Arg(1)),
	-- TODO StoreName 'func'
	ForRange('i', Arg(1),
		StoreNameInt(Add('rollingbase', Mul(Arg(LoadNameInt('i')), Int(4)))),
		WriteDataframe(
			Add(LoadNameInt('baseframe'), LoadNameInt('i')),
			If(LoadNameInt('i'), 3, 1), -- type = i ? call : norm
			Int(0), -- pc
			LoadNameInt('rollingbase'), -- base
			Mul(LoadFuncParamc(LoadName('func')), 4), -- dotdotdot
			Int(-4), -- retb
			Int(-1), -- retc
			0, --  TODO calc locals
			0 -- TODO calc frame
		)
	)
)

ops[bc.CmpEq] = Seq(
	StoreName('a', Pop()),
	StoreName('b', Pop()),
	If(
		ObjMetalessEq(LoadName('a'), LoadName('b')),
		Push(TrueAtom),
		If(
			And(
				Eq(Type(LoadName('a')), Int(types.tbl)),
				Eq(Type(LoadName('b')), Int(types.tbl))
			),
			If(
				Eq(Meta(LoadName('a')), Meta(LoadName('b'))),
				Push(TrueAtom),-- CALL META
				Push(FalseAtom)
			),
			Push(FalseAtom)
		)
	)
)

return {
	mops = mops,
	ops = ops,
}

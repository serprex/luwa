local bc = require 'bc'
local alloc = require 'alloc'
local types = alloc.types
local mtypes = {}
local mops = {}
local mopmt__index = {}
local mopmt = { __index = mopmt__index }
local function mkMop(op, sig)
	local id = #mops+1
	mops[id] = {
		op = op,
		sig = sig,
	}
	mops[op] = id
	mopmt__index[op] = function(f, ...)
		local instr = { op = id, ... }
		for i = 1, #instr do
			local x = instr[i]
			if type(x) == 'function' then
				local g = setmetatable({ op = -1, ops = {} }, mopmt)
				x(g)
				instr[i] = g
			end
		end
		f.ops[#f.ops + 1] = instr
		return instr
	end
end
local function mkOp(op, func)
	local f = setmetatable({ ops = {} }, mopmt)
	func(f)
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
mkMop('Nop', {})
mkMop('Int', {
	arg = {'Lint'},
	out = 'i32',
})
mkMop('Str', {
	arg = {'Lstr'},
	out = 'str',
})
mkMop('Load', {
	arg = {'i32'},
	out = {'i32'},
})
mkMop('LoadInt', {
	arg = {'obj'},
	out = {'i64'},
})
mkMop('LoadFlt', {
	arg = {'obj'},
	out = {'f64'},
})
mkMop('Free', {
	arg = {'i32'},
	out = {'obj'},
})
mkMop('Store', {
	arg = { 'i32', 'i32' },
})
mkMop('Eq', {
	arg = { 'i32', 'i32' },
	out = 'i32',
})
-- TODO need to work out concept of 'deferred' block in arg sig
-- ie we're mixing up idea of input vs argument
mkMop('If', function(args)
	local _then, _else = out(args[2]), args[2] and out(args[2])
	assert(_then == _else, "If's branches with unequal type")
	return {
		arg = { 'i32' },
		out = _then,
	}
end)
mkMop('In')
mkMop('Arg', {
	arg = { 'Lint' },
	out = { 'i32' },
})
mkMop('Push', {
	alloc = true,
	arg = {'obj'},
	out = {},
})
mkMop('Pop', {
	arg = {},
	out = {'obj'},
})
mkMop('SetPc', {
	arg = {'i32'},
	out = {},
})
mkMop('Truthy', {
	arg = {'obj'},
	out = 'i32',
})
mkMop('Box', {
	alloc = true,
	arg = {'obj'},
	out = {'obj'},
})
mkMop('CloneFunc', {
	alloc = true,
	arg = {'obj'},
	out = {'obj'},
})
mkMop('ObjMetalessEq', {
	arg = {'obj', 'obj'},
	out = {'i32'},
})
mkMop('IntObjFromInt', {
	alloc = true,
	arg = {'i32'},
	out = {'obj'},
})
mkMop('LoadStrLen', {
	arg = {'obj'},
	out = {'i32'},
})
mkMop('Error')
mkMop('Syscall', {
	alloc = true,
	arg = {'i32'},
	out = {},
})
mkMop('Int2Flt', {
	arg = {'i64'},
	out = {'f64'},
})
mkMop('Flt2Int', {
	arg = {'f64'},
	out = {'i64'},
})
function mopmt__index:Nil()
	return self:Int(0)
end
function mopmt__index:False()
	return self:Int(4)
end
function mopmt__index:True()
	return self:Int(8)
end
local ops = {}
mkOp(bc.Nop, function(f) end)
mkOp(bc.LoadNil, function(f)
	f:Push(f:Nil())
end)
mkOp(bc.LoadFalse, function(f)
	f:Push(f:False())
end)
mkOp(bc.LoadTrue, function(f)
	f:Push(f:True())
end)
mkOp(bc.LoadParam, function(f)
	f:Push(f:Load(f:Param(f:Arg(0))))
end)
mkOp(bc.StoreParam, function(f)
	f:Store(f:Param(f:Arg(0)), f:Pop())
end)
mkOp(bc.LoadLocal, function(f)
	f:Push(f:Load(f:Local(f:Arg(0))))
end)
mkOp(bc.StoreLocal, function(f)
	f:Store(f:Local(f:Arg(0)), f:Pop())
end)
mkOp(bc.LoadFree, function(f)
	f:Push(f:Load(f:Free(f:Arg(0))))
end)
mkOp(bc.LoadFreeBox, function(f)
	f:Push(f:Load(f:Load(f:Free(f:Arg(0)))))
end)
mkOp(bc.StoreFreeBox, function(f)
	f:Store(f:Load(f:Free(f:Arg(0))), f:Pop())
end)
mkOp(bc.LoadParamBox, function(f)
	f:Push(f:Load(f:Load(f:Param(f:Arg(0)))))
end)
mkOp(bc.StoreParamBox, function(f)
	f:Store(f:Load(f:Param(f:Arg(0))), f:Pop())
end)
mkOp(bc.BoxParam, function(f)
	f:Store(f:Param(0), f:Box(f:Param(f:Arg(0))))
end)
mkOp(bc.BoxLocal, function(f)
	f:Store(f:Local(0), f:Box(f:Nil()))
end)
mkOp(bc.LoadLocalBox, function(f)
	f:Push(f:Load(f:Load(f:Local(f:Arg(0)))))
end)
mkOp(bc.StoreLocalBox, function(f)
	f:Store(f:Load(f:Local(f:Arg(0))), f:Pop())
end)
mkOp(bc.LoadConst, function(f)
	f:Push(f:Load(f:Const(f:Arg(0))))
end)
mkOp(bc.Pop, function(f)
	f:Pop()
end)
mkOp(bc.Syscall, function(f)
	f:Syscall(f:Arg(0))
end)
mkOp(bc.Jmp, function(f)
	f:SetPc(f:Arg(0))
end)
mkOp(bc.JifNot, function(f)
	f:If(
		f:Truthy(f:Pop()),
		function(f)
			f:SetPc(f:Arg(0))
		end
	)
end)
mkOp(bc.Jif, function(f)
	f:If(
		f:Truthy(f:Pop()),
		function(f) end,
		function(f)
			f:SetPc(f:Arg(0))
		end
	)
end)
mkOp(bc.JifNotOrPop, function(f)
	f:If(
		f:Truthy(f:Peek()),
		function(f)
			f:SetPc(f:Arg(0))
		end,
		function(f)
			f:Pop()
		end
	)
end)
mkOp(bc.JifOrPop, function(f)
	f:If(
		f:Truthy(f:Peek()),
		function(f)
			f:Pop()
		end,
		function(f)
			f:SetPc(f:Arg(0))
		end
	)
end)
mkOp(bc.LoadFunc, function(f)
	local func = f:CloneFunc(f:Const(f:Arg(1)))
	f:If(
		f:Arg(0),
		function(f)
			f:Store(
				f:Add(func, f:Int(functy.frees)),
				f:FillFromStack(f:NewVec(f:Arg(0)), f:Arg(0))
			)
		end
	)
	f:Push(func)
end)
mkOp(bc.LoadVarg, function(f)
	-- TODO AllocateTemp points inside an object, needs special book keeping over allocation barriers
	local tmp = f:AllocateTemp(f:Arg(0))
	local vlen = f:VargLen()
	local vptr = f:VargPtr()
	f:If(
		f:Lt(vlen, f:Arg(0)),
		function(f)
			local vlen4 = f:Mul(vlen, f:Int(2))
			f:MemCpy4(tmp, vptr, vlen4)
			f:FillRange(f:Add(tmp, vlen4), NilAtom, f:Mul(f:Sub(f:Arg(0), vlen), f:Int(2)))
		end,
		function(f)
			f:MemCpy4(tmp, vptr, f:Mul(f:Arg(0), f:Int(2)))
		end
	)
end)
mkOp(bc.AppendVarg, function(f)
	f:AppendRange(f:Pop(), f:VargPtr(), f:Arg(0))
end)
-- TODO
mkOp(bc.Call, function(f)
	local nret = f:Arg(0)
	local baseframe = f:DataFrameTop()
	local rollingbase = f:AllocateTemp(f:Int(1))
	f:Store(rollingbase, f:DataFrameTopBase())
	f:AllocateDataFrames(f:Arg(1))
	-- TODO StoreName 'func'
	f:ForRange(f:Int(0), f:Arg(1), function(i)
		f:Store(rollingbase, f:Add(f:Load(rollingbase), f:Mul(f:LoadArg(f:LoadNameInt('i')), f:Int(4))))
		f:WriteDataFrame(
			f:Add(baseframe, i),
			f:If(i,
				function(f)
					f:Int(3)
				end,
				function(f)
					f:Int(1)
				end), -- type = i ? call : norm
			f:Int(0), -- pc
			rollingbase, -- base
			f:Mul(f:LoadFuncParamc(func), f:Int(4)), -- dotdotdot
			f:Int(-4), -- retb
			f:Int(-1), -- retc
			0, --  TODO calc locals
			0 -- TODO calc frame
		)
	end)
	f:PushObjFrameFromFunc(func)
	f:SetPc(f:Int(0))
end)

-- TODO replace f:If with something that'll compile to wasm's select
mkOp(bc.Not, function(f)
	f:Push(
		f:If(f:Truthy(f:Pop()),
			function(f) return f:False() end,
			function(f) return f:True() end)
	)
end)

mkOp(bc.Len, function(f)
	local a = f:Pop()
	local aty = f:Type(a)
	f:If(
		f:Eq(aty, f:Int(types.str)),
		function(f) f:Push(f:IntObjFromInt(f:LoadStrLen(a))) end,
		function(f)
			f:If(
				f:Eq(aty, f:Int(types.tbl)),
				function(f)
					local ameta = f:Meta(a)
					f:If(ameta,
						function(f) f:CallMetaMethod('__len', ameta, a) end, -- TODO helper function this
						function(f) f:Push(f:IntObjFromInt(f:LoadTblLen(a))) end
					)
				end,
				function(f) f:Error() end
			)
		end
	)
end)

mkOp(bc.Neg, function(f)
	local a = f:Pop()
	local aty = f:Type(a)
	f:Typeck({a},
		{
			types.int,
			function(f)
				f:NegateInt(a)
			end,
		}, {
			types.float,
			function(f)
				f:NegateFloat(a)
			end,
		},
		{
			types.str,
			function(f)
				f:NegateFloat(f:ParseFloat(a))
			end,
		},
		{
			types.tbl,
			function(f)
				local ameta = f:Meta(a)
				f:If(ameta,
					function(f) f:CallMetaMethod('__neg', ameta, a) end, -- TODO helper function this
					function(f)
						-- TODO error
					end
				)
			end,
		},
		function(f)
			-- TODO error
		end
	)
end)

mkOp(bc.TblNew, function(f)
	f:Push(f:NewTbl())
end)
mkOp(bc.TblAdd, function(f)
	local v = f:Pop()
	local k = f:Pop()
	local tbl = f:Pop()
	f:TblSet(tbl, k, v)
	f:Pop()
	f:Pop()
end)

mkOp(bc.CmpEq, function(f)
	local a = f:Pop()
	local b = f:Pop()
	f:If(
		f:ObjMetalessEq(a, b),
		function(f) f:Push(f:True()) end,
		function(f)
			f:If(
				f:And(
					f:Eq(f:Type(a), f:Int(types.tbl)),
					f:Eq(f:Type(b), f:Int(types.tbl))
				),
				function(f)
					local amt = f:Meta(a)
					local bmt = f:Meta(b)
					f:If(
						f:And(amt, bmt),
						function(f)
							local amteq = f:TblGet(amt, f:Str('__eq'))
							local bmteq = f:TblGet(bmt, f:Str('__eq'))
							f:If(
								f:Eq(amteq, bmteq),
								function(f)
									-- TODO call as boolret
									f:BoolCall(amteq, a, b)
								end, -- CALL META
								function(f) f:Push(f:False()) end
							)
						end,
						function(f) f:Push(f:False()) end
					)
				end,
				function(f) f:Push(f:False()) end
			)
		end
	)
end)

function cmpop(op, cmpop, strlogic)
	mkOp(op, function(f)
		local a = f:Pop()
		local b = f:Pop()
		f:Typeck({a, b},
			{
				types.int,
				types.int,
				function(f)
					f:Push(f:If(
						f[cmpop](f, f:LoadInt(a), f:LoadInt(b)),
						function(f) return f:True() end,
						function(f) return f:False() end
					))
				end,
			},
			{
				types.float,
				types.float,
				function(f)
					f:Push(f:If(
						f[cmpop](f, f:LoadFlt(a), f:LoadFlt(b)),
						function(f) return f:True() end,
						function(f) return f:False() end
					))
				end,
			},
			{
				types.str,
				types.str,
				function(f)
					f:Push(f:If(
						f[cmpop](f, f:StrCmp(a, b), f:Int(0)),
						function(f) return f:True() end,
						function(f) return f:False() end
					))
				end,
			},
			{
				types.int,
				types.float,
				function(f)
					f:Push(f:If(
						f[cmpop](f, f:Int2Flt(f:LoadInt(a)), f:LoadFlt(b)),
						function(f) return f:True() end,
						function(f) return f:False() end
					))
				end,
			},
			{
				types.float,
				types.int,
				function(f)
					f:Push(f:If(
						f[cmpop](f, f:LoadFlt(a), f:Int2Flt(f:LoadInt(b))),
						function(f) f:True() end,
						function(f) f:False() end
					))
				end,
			},
			function(f)
				-- TODO metamethod fallbacks, error otherwise
			end
		)
	end)
end
cmpop(bc.CmpLe, 'Le')
cmpop(bc.CmpLt, 'Lt')
cmpop(bc.CmpGe, 'Ge')
cmpop(bc.CmpGt, 'Gt')

function binmathop(op, floatlogic, intlogic, metamethod)
	mkOp(op, function(f)
		local a = f:Pop()
		local b = f:Pop()
		f:Typeck({a, b},
		{
			types.int,
			types.int,
			function(f)
				f:Push(intlogic(f, f:LoadInt(a), f:LoadInt(b)))
			end
		},{
			types.float,
			types.float,
			function(f)
				f:Push(floatlogic(f, f:LoadFlt(a), f:LoadFlt(b)))
			end
		},{
			types.int,
			types.float,
			function(f)
				f:Push(floatlogic(f, f:Int2Flt(f:LoadInt(a)), f:LoadFlt(b)))
			end
		},{
			types.float,
			types.int,
			function(f)
				f:Push(floatlogic(f, f:LoadFlt(a), f:Int2Flt(f:LoadInt(b))))
			end
		})
	end)
end
function binmathop_mono(op, mop, metamethod)
	function logic(f, a, b)
		return f[mop](a, b)
	end
	return binmathop(op, logic, logic, metamethod)
end
binmathop_mono(bc.Add, 'Add', '__add')
binmathop_mono(bc.Sub, 'Sub', '__sub')
binmathop_mono(bc.Mul, 'Mul', '__mul')
binmathop(bc.Div,
	function(f, a, b)
		return f:Div(f:Flt2Int(a), f:Flt2Int(b))
	end,
	function(f, a, b)
		return f:Div(a, b)
	end,
	'__div')
mkOp(bc.IDiv, function(f)
	local a = f:Pop()
	local b = f:Pop()
	f:Typeck({a, b},
	{
		types.int,
		types.int,
		function(f)
			f:Push(f:Div(f:LoadInt(a), f:LoadInt(b)))
		end
	},{
		types.float,
		types.float,
		function(f)
			f:Push(f:Div(f:Flt2Int(f:LoadFlt(a)), f:Flt2Int(f:LoadFlt(b))))
		end
	},{
		types.int,
		types.float,
		function(f)
			f:Push(f:Div(f:LoadInt(a), f:Flt2Int(f:LoadFlt(b))))
		end
	},{
		types.float,
		types.int,
		function(f)
			f:Push(f:Div(f:Flt2Int(f:LoadFlt(a)), f:LoadInt(b)))
		end
	})
end)
binmathop(bc.Pow,
	function(f, a, b)
		return f:Pow(f:Flt2Int(a), f:Flt2Int(b))
	end,
	function(f, a, b)
		return f:Pow(a, b)
	end,
	'__pow')
binmathop_mono(bc.Mod, 'Mod', '__mod')
function binbitop(op, mop, metamethod)
	mkOp(op, function(f)
		local a = f:Pop()
		local b = f:Pop()
		f:Typeck({a, b},
		{
			types.int,
			types.int,
			function(f)
				f:Push(f[mop](f, f:LoadInt(a), f:LoadInt(b)))
			end
			-- TODO assert floats are integer compatible
		},{
			types.float,
			types.float,
			function(f)
				f:Push(f[mop](f, f:Flt2Int(f:LoadFlt(a)), f:Flt2Int(f:LoadFlt(b))))
			end
		},{
			types.int,
			types.float,
			function(f)
				f:Push(f[mop](f, f:LoadInt(a), f:Flt2Int(f:LoadFlt(b))))
			end
		},{
			types.float,
			types.int,
			function(f)
				f:Push(f[mop](f, f:Flt2Int(f:LoadFlt(a)), f:LoadInt(b)))
			end
		})
	end)
end
binbitop(bc.BAnd, 'BAnd', '__band')
binbitop(bc.BOr, 'BOr', '__bor')
binbitop(bc.BXor, 'BXor', '__bxor')
binbitop(bc.Shr, 'Shr', '__shr')
binbitop(bc.Shl, 'Shl', '__shl')
mkOp(bc.BNot, function()
	local a = f:Pop()
	f:Typeck({a},
	{
		types.int,
		function(f)
			f:Push(f:BNot(f:LoadInt(a)))
		end
	},{
		types.float,
		function(f)
			f:Push(f:BNot(f:Flt2Int(f:LoadFlt(a))))
		end
	},
	function(f)
		local ameta = f:Meta(a)
		f:If(ameta,
			function(f) f:CallMetaMethod('__bnot', ameta, a) end, -- TODO helper function this
			function(f) f:Error() end
		)
	end)
end)

-- bc.Concat
-- bc.Idx
-- bc.Append

return {
	mops = mops,
	ops = ops,
}

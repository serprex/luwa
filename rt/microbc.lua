local bc = require 'bc'
local alloc = require 'alloc'
local types = alloc.types
local mops = {}
local mopmt__index = {}
local mopmt = { __index = mopmt__index }
local function mkMop(op)
	local id = #mops+1
	mops[id] = op
	mops[op] = id
	mopmt__index[op] = function(f, ...)
		f.ops[#f.ops] = { op = id, ... }
	end
end
local function mkOp(op, func)
	local f = setmetatable({}, mopmt)
	func(f)
	ops[op] = f
end
mkMop('Nop')
mkMop('Int')
mkMop('Load')
mkMop('Store')
mkMop('Eq')
mkMop('If')
mkMop('In')
mkMop('Arg')
mkMop('Push')
mkMop('Truthy')
mkMop('CloneFunc')
mkMop('ObjMetalessEq')
mkMop('IntObjFromInt')
mkMop('LoadStrLen')
mkMop('Error')
mkMop('Macro')
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
mkOp(bc.Nop, function()
end)
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
	f:Store(Load(Free(Arg(0))), Pop())
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
		function()
			f:SetPc(f:Arg(0))
		end
	)
end)
mkOp(bc.Jif, function(f)
	f:If(
		f:Truthy(f:Pop()),
		function() end,
		f:SetPc(f:Arg(0))
	)
end)
mkOp(bc.LoadFunc, function(f)
	local func = f:CloneFunc(f:Const(f:Arg(1)))
	f:If(
		f:Arg(0),
		function()
			f:Store(
				f:Add(func, f:Int(functy.frees)),
				f:FillFromStack(f:NewVec(f:Arg(0)), f:Arg(0))
			)
		end
	)
	f:Push(func)
end)
mkOp(bc.LoadVarg, function(f)
	local tmp = AllocateTemp(Arg(0))
	local vlen = VargLen()
	local vptr = VargPtr()
	f:If(
		f:Lt(vlen, f:Arg(0)),
		function()
			local vlen4 = f:Mul(vlen, f:Int(2))
			f:MemCpy4(tmp, vptr, vlen4)
			f:FillRange(f:Add(tmp, vlen4), NilAtom, f:Mul(f:Sub(f:Arg(0), vlen), f:Int(2)))
		end,
		function()
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
	local rollingbase = f:DataFrameTopBase()
	f:AllocateDataFrames(f:Arg(1))
	-- TODO StoreName 'func'
	ForRange(Int(0), Arg(1), function(i)
		-- TODO SSA this:
		-- rollingbase = Add(rollingbase, Mul(Arg(LoadNameInt('i')), Int(4)))
		WriteDataFrame(
			f:Add(baseframe, i),
			f:If(i,
				function()
					f:Int(3)
				end,
				function()
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

mkOp(bc.Not, function(f)
	f:Push(
		f:If(f:Truthy(f:Pop()),
			function() f:False() end,
			function() f:True() end)
	)
end)

mkOp(bc.Len, function(f)
	local a = f:Pop()
	local aty = f:Type(a)
	f:If(
		f:Eq(aty, f:Int(types.str)),
		function() f:Push(f:IntObjFromInt(f:LoadStrLen(a))) end,
		function()
			f:If(
				f:Eq(aty, f:Int(types.tbl)),
				function()
					local ameta = Meta(a)
					f:If(ameta,
						function() f:CallMetaMethod('__len') end -- TODO helper function this
					)
				end,
				function() f:Error() end
			)
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
		function() f:Push(f:True()) end,
		f:If(
			f:And(
				f:Eq(f:Type(a), f:Int(types.tbl)),
				f:Eq(f:Type(b), f:Int(types.tbl))
			),
			function()
				f:If(
					f:Eq(f:Meta(a), f:Meta(b)),
					function() f:Push(f:True()) end, -- CALL META
					function() f:Push(f:False()) end
				)
			end,
			function() f:Push(f:False()) end
		)
	)
end)

return {
	mops = mops,
	ops = ops,
}

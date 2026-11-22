require 'rt' -- sets NIL/FALSE/TRUE globals
local alloc = require 'alloc'
local types = alloc.types
local bc = require 'bc'

-- Each bytecode op is a block: a list of statements, built in order by calling the block's methods.
-- Pure mops (math, compares, constants, reads of fields that never change) are plain functions
-- that build expression trees. Everything else is a statement, made with b:Name(...):
-- the statement runs where it's added, and its value (if any) can be used by later statements.
-- If & Typeck are statements holding nested blocks.
local mops = {}
local ops = {}
-- ops whose microcode doesn't typecheck yet: op -> error message
local broken = {}

-- Object types narrower than obj. Typeck branches see their operands as these,
-- and mops that need a certain kind of object take these types
local objtypes = { obj = true, int = true, float = true, str = true, tbl = true }
local narrowtype = {
	[types.int] = 'int',
	[types.float] = 'float',
	[types.str] = 'str',
	[types.tbl] = 'tbl',
}
local function subtype(t, want)
	return t == want or (want == 'obj' and objtypes[t] ~= nil)
end
-- Type that both a and b fit in, or nil
local function join(a, b)
	if a == b then
		return a
	elseif objtypes[a] and objtypes[b] then
		return 'obj'
	end
end

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
		if a ~= 'atom' and not subtype(out(mop[i]), a) then
			mop.err = mop.err or (mops[mop.op] .. ': arg ' .. i .. ' expected ' .. tostring(a) .. ' got ' .. tostring(out(mop[i])))
		end
	end
end

local Block = {}
Block.__index = Block
local function newblock(parent)
	return setmetatable({ parent = parent, stmts = {} }, Block)
end
function Block:add(node)
	assert(not node.block, 'statement added twice')
	node.block = self
	self.stmts[#self.stmts+1] = node
	return node
end
-- New block nested in this one. fn(blk, ...) fills it, what fn returns is the block's value
function Block:sub(fn, ...)
	local blk = newblock(self)
	blk.result = fn(blk, ...)
	return blk
end

-- sig is a table, or a function given the new node that returns one.
-- sig.stmt marks a statement, so do alloc & exit. sig.argfx means codegen
-- does side effects between evaluating the args
local function mkMop(name, sig)
	local id = #mops+1
	mops[id] = name
	mops[name] = id
	local function ctor(...)
		local node = { op = id, ... }
		local meta = sig
		if type(sig) == 'function' then
			local ok, m = pcall(sig, node)
			if not ok then
				node.err = name .. ': ' .. tostring(m)
				return node
			end
			meta = m
		end
		for k,v in pairs(meta) do
			node[k] = v
		end
		if node.alloc or node.exit then
			node.stmt = true
		end
		verify(node)
		return node
	end
	Block[name] = function(self, ...)
		local node = ctor(...)
		if not node.stmt then
			error(name .. ' is pure, call it without the block')
		end
		return self:add(node)
	end
	return ctor
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
-- A constant value: NIL, FALSE or TRUE
local Obj = mkMop('Obj', {
	arg = {'atom'},
	out = 'obj',
})
local Str = mkMop('Str', {
	arg = {'atom'},
	out = 'str',
})
-- Treat an object as a narrower type without checking.
-- Only for values known by construction, Typeck is the checked way
local As = mkMop('As', function(args)
	assert(objtypes[args[2]], 'As: not an object type')
	return {
		arg = {'obj', 'atom'},
		out = args[2],
	}
end)
-- A number (int or float) as a string
mkMop('ToString', {
	alloc = true,
	arg = {'obj'},
	out = 'str',
})
local LoadInt = mkMop('LoadInt', {
	arg = {'int'},
	out = 'i64',
})
local LoadFlt = mkMop('LoadFlt', {
	arg = {'float'},
	out = 'f64',
})
-- Slots of the current function. Index comes first, value to store second
-- Local/Param live on the lua stack, Free/Const in the function's vecs
mkMop('LoadLocal', {
	stmt = true,
	arg = {'i32'},
	out = 'obj',
})
mkMop('StoreLocal', {
	stmt = true,
	arg = {'i32', 'obj'},
})
mkMop('LoadParam', {
	stmt = true,
	arg = {'i32'},
	out = 'obj',
})
mkMop('StoreParam', {
	stmt = true,
	arg = {'i32', 'obj'},
})
-- Frees & consts don't change while a function runs
local LoadFree = mkMop('LoadFree', {
	arg = {'i32'},
	out = 'obj',
})
local LoadConst = mkMop('LoadConst', {
	arg = {'i32'},
	out = 'obj',
})
-- Value inside a box (a vec of length 1)
mkMop('Unbox', {
	stmt = true,
	arg = {'obj'},
	out = 'obj',
})
mkMop('SetBox', {
	stmt = true,
	arg = {'obj', 'obj'},
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
mkMop('NegateInt', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
mkMop('NegateFloat', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
mkMop('StrConcat', {
	alloc = true,
	arg = {'str','str'},
	out = 'obj',
})
-- c ? a : b, on pure values. Only the chosen one is evaluated
local Select = mkMop('Select', function(args)
	local t = join(out(args[2]), out(args[3]))
	assert(t, 'Select: branches with unequal type')
	return {
		arg = {'i32', t, t},
		out = t,
	}
end)
local Arg = mkMop('Arg', {
	arg = { 'atom' },
	out =  'i32' ,
})
mkMop('Push', {
	stmt = true,
	arg = {'obj'},
})
mkMop('Pop', {
	stmt = true,
	arg = {},
	out = 'obj',
})
mkMop('Peek', {
	stmt = true,
	arg = {},
	out = 'obj',
})
mkMop('SetPc', {
	exit = true,
	arg = {'i32'},
})
local Truthy = mkMop('Truthy', {
	arg = {'obj'},
	out = 'i32',
})
mkMop('Box', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
local ObjMetalessEq = mkMop('ObjMetalessEq', {
	arg = {'obj', 'obj'},
	out = 'i32',
})
mkMop('IntObjFromInt', {
	alloc = true,
	arg = {'i32'},
	out = 'int',
})
mkMop('IntObjFromInt64', {
	alloc = true,
	arg = {'i64'},
	out = 'int',
})
mkMop('FltObjFromFlt', {
	alloc = true,
	arg = {'f64'},
	out = 'float',
})
local LoadStrLen = mkMop('LoadStrLen', {
	arg = {'str'},
	out = 'i32',
})
-- Error(kind, operands...) raises a runtime error, see vm.lua. Error() raises 'invalid operation'
mkMop('Error', function(args)
	local arg = { 'atom' }
	for i=2,#args do
		arg[i] = 'obj'
	end
	return { arg = #args > 0 and arg or nil, exit = true, argfx = true }
end)
-- Builtin written in wasm, reads its own 1 byte arg
mkMop('Syscall', {
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
	arg = {'tbl'},
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
local IsTblOrVec = mkMop('IsTblOrVec', {
	arg = {'obj'},
	out = 'i32',
})
local IsNumOrStr = mkMop('IsNumOrStr', {
	arg = {'obj'},
	out = 'i32',
})
mkMop('TblGet', {
	stmt = true,
	arg = {'tbl', 'obj'},
	out = 'obj',
})
mkMop('TblSet', {
	alloc = true,
	arg = {'tbl', 'obj', 'obj'},
})
-- tbllen allocates a temporary int
mkMop('LoadTblLen', {
	alloc = true,
	arg = {'tbl'},
	out = 'i32',
})
local LoadFuncParamc = mkMop('LoadFuncParamc', {
	arg = {'obj'},
	out = 'i32',
})
-- Metatable field, nil without a metatable. Strings use the string metatable
mkMop('MetaGet', {
	stmt = true,
	arg = {'obj', 'str'},
	out = 'obj',
})
-- Metamethod for a binary op: first operand's, else second's
mkMop('BinMeta', {
	stmt = true,
	arg = {'obj', 'obj', 'str'},
	out = 'obj',
})
-- a[b] following __index tables. If it ends at an __index function,
-- that's the result & IdxSelf is what to call it with, otherwise IdxSelf is 0
mkMop('IdxWalk', {
	stmt = true,
	arg = {'obj', 'obj'},
	out = 'obj',
})
-- a[b] = c following __newindex tables. Gives nil once stored, or an __newindex
-- function to call with IdxSelf, b & c. a has to be a table or have a __newindex
mkMop('NewIdxWalk', {
	stmt = true,
	alloc = true,
	arg = {'obj', 'obj', 'obj'},
	out = 'obj',
})
mkMop('IdxSelf', {
	stmt = true,
	out = 'obj',
})
-- Call a function with some args, its 1 result is pushed when it returns.
-- First arg is the call type: 'norm', 'bool' to make the result true/false, or 'none' to keep no result.
-- Leaves the op, so it has to come last. Pushes each arg as it goes
mkMop('CallMeta', function(args)
	local arg = { 'atom' }
	for i=2,#args do
		arg[i] = 'obj'
	end
	return { arg = arg, exit = true, argfx = true }
end)
-- Call op family, reads its own bytecode args. Args: call type, whether to pass varargs too
mkMop('CallChain', {
	exit = true,
	arg = {'atom', 'atom'},
})
-- Return everything after the frame's locals
mkMop('Ret', {
	exit = true,
})
-- Push all varargs
mkMop('VargPush', {
	stmt = true,
})
-- Push the first n varargs, nil filled
mkMop('VargPushN', {
	stmt = true,
	arg = {'i32'},
})
-- Stack is table then n values: set them as t[1..n], leave the table
mkMop('AppendN', {
	alloc = true,
	arg = {'i32'},
})
-- How many varargs this frame got
mkMop('VargCount', {
	stmt = true,
	out = 'i32',
})
-- Like AppendN, with varargs after the n values
mkMop('AppendVarg', {
	alloc = true,
	arg = {'i32'},
})
-- Copy of a function proto, the top n values are popped as its frees
mkMop('MakeClosure', {
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
	arg = {'str', 'str'},
	out = 'i32',
})
mkMop('NewTbl', {
	alloc = true,
	out = 'tbl',
})

-- Type of an If or Typeck: its branches' common result type.
-- If any branch has no result, there's no result & branch results are dropped
local function branchtype(blocks, hasDefault)
	local t
	for i, blk in ipairs(blocks) do
		local bt = out(blk.result)
		t = i == 1 and bt or (t and bt and join(t, bt))
		if not t then
			break
		end
	end
	if not hasDefault then
		t = nil
	end
	if not t then
		for _, blk in ipairs(blocks) do
			blk.result = nil
		end
	end
	return t
end
local IfMop = mkMop('If', {
	stmt = true,
	arg = { 'i32' },
})
-- b:If(cond, function(b) ... end, function(b) ... end), else is optional
function Block:If(cond, thenf, elsef)
	local node = IfMop(cond)
	node.thenb = self:sub(thenf)
	node.elseb = elsef and self:sub(elsef)
	node.blocks = { node.thenb, node.elseb }
	node.out = branchtype(node.blocks, elsef ~= nil)
	return self:add(node)
end
function Block:IfNot(cond, thenf, elsef)
	return self:If(Eq(cond, Int(0)), thenf, elsef)
end
local TypeckMop = mkMop('Typeck', function(args)
	assert(#args > 0, 'Typeck expects values to check')
	local arg = {}
	for i=1,#args do
		arg[i] = 'obj'
	end
	return { stmt = true, arg = arg }
end)
-- b:Typeck({x, y}, {
--	{types.int, types.int, function(b, x, y) ... end},
--	...
-- }, function(b) ... end)
-- Runs the first case whose type ids match the values' types, else the default (optional).
-- A case's function gets the values narrowed to its types
function Block:Typeck(vals, cases, default)
	local n = #vals
	local node = TypeckMop(table.unpack(vals, 1, n))
	node.cases = {}
	node.blocks = {}
	for i, case in ipairs(cases) do
		local tys = {}
		for j=1,n do
			tys[j] = case[j]
			assert(type(tys[j]) == 'number', 'Typeck expects type ids')
		end
		local fn = assert(case[n+1], 'Typeck case without a body')
		local blk = newblock(self)
		local narrowed = {}
		for j=1,n do
			local ty = narrowtype[tys[j]]
			if ty then
				narrowed[j] = As(vals[j], ty)
				-- only valid inside this case
				narrowed[j].block = blk
			else
				narrowed[j] = vals[j]
			end
		end
		blk.result = fn(blk, table.unpack(narrowed, 1, n))
		node.cases[i] = { tys = tys, block = blk }
		node.blocks[i] = blk
	end
	if default then
		node.default = self:sub(default)
		node.blocks[#node.blocks+1] = node.default
	end
	node.out = branchtype(node.blocks, default ~= nil)
	return self:add(node)
end

-- Is blk def, or nested inside it?
local function visible(def, blk)
	while blk do
		if blk == def then
			return true
		end
		blk = blk.parent
	end
	return false
end
-- First error in an expression used in blk, or nil
local function checktree(node, blk)
	if type(node) == 'function' then
		return 'Lua function used where microcode expected'
	end
	if type(node) ~= 'table' then
		return nil
	end
	if not node.op then
		return 'not a microcode node'
	end
	if node.err then
		return node.err
	end
	if node.stmt and not node.block then
		return mops[node.op] .. ' is a statement, call it on the block'
	end
	if node.block and not visible(node.block, blk) then
		return mops[node.op] .. ' value used outside the block that made it'
	end
	if node.stmt then
		-- its args were checked where it was added
		return nil
	end
	for i=1,#node do
		local err = checktree(node[i], blk)
		if err then
			return err
		end
	end
end
local function checkblock(blk)
	for _, s in ipairs(blk.stmts) do
		if s.err then
			return s.err
		end
		for i=1,#s do
			local err = checktree(s[i], blk)
			if err then
				return err
			end
		end
		for _, sub in ipairs(s.blocks or {}) do
			local err = checkblock(sub)
			if err then
				return err
			end
		end
	end
	return checktree(blk.result, blk)
end
-- Call fn on every node in blk & its nested blocks, once each
local function walk(blk, fn, seen)
	seen = seen or {}
	local function tree(node)
		if type(node) ~= 'table' or seen[node] then
			return
		end
		seen[node] = true
		fn(node)
		for i=1,#node do
			tree(node[i])
		end
	end
	for _, s in ipairs(blk.stmts) do
		tree(s)
		for _, sub in ipairs(s.blocks or {}) do
			walk(sub, fn, seen)
		end
	end
	tree(blk.result)
end

-- Define op's microcode: fn(b) adds its statements to block b
local function op(code, fn)
	assert(code, 'op: unknown bytecode op')
	local blk = newblock(nil)
	local ok, err = pcall(fn, blk)
	if ok then
		err = checkblock(blk)
	end
	if err then
		broken[code] = tostring(err)
	else
		ops[code] = blk
	end
end

-- Box an i64 or f64 into a number object
local function NumObj(b, x)
	if out(x) == 'f64' then
		return b:FltObjFromFlt(x)
	else
		return b:IntObjFromInt64(x)
	end
end
local function Nil() return Obj(NIL) end
local function False() return Obj(FALSE) end
local function True() return Obj(TRUE) end
op(bc.Nop, function(b) end)
op(bc.LoadNil, function(b) b:Push(Nil()) end)
op(bc.LoadFalse, function(b) b:Push(False()) end)
op(bc.LoadTrue, function(b) b:Push(True()) end)
op(bc.LoadParam, function(b) b:Push(b:LoadParam(Arg(0))) end)
op(bc.StoreParam, function(b) b:StoreParam(Arg(0), b:Pop()) end)
op(bc.LoadLocal, function(b) b:Push(b:LoadLocal(Arg(0))) end)
op(bc.StoreLocal, function(b) b:StoreLocal(Arg(0), b:Pop()) end)
op(bc.LoadFree, function(b) b:Push(LoadFree(Arg(0))) end)
op(bc.LoadFreeBox, function(b) b:Push(b:Unbox(LoadFree(Arg(0)))) end)
op(bc.StoreFreeBox, function(b) b:SetBox(LoadFree(Arg(0)), b:Pop()) end)
op(bc.LoadParamBox, function(b) b:Push(b:Unbox(b:LoadParam(Arg(0)))) end)
op(bc.StoreParamBox, function(b)
	local v = b:Pop()
	b:SetBox(b:LoadParam(Arg(0)), v)
end)
op(bc.BoxParam, function(b) b:StoreParam(Arg(0), b:Box(b:LoadParam(Arg(0)))) end)
op(bc.BoxLocal, function(b) b:StoreLocal(Arg(0), b:Box(Nil())) end)
op(bc.LoadLocalBox, function(b) b:Push(b:Unbox(b:LoadLocal(Arg(0)))) end)
op(bc.StoreLocalBox, function(b)
	local v = b:Pop()
	b:SetBox(b:LoadLocal(Arg(0)), v)
end)
op(bc.LoadConst, function(b) b:Push(LoadConst(Arg(0))) end)
op(bc.Pop, function(b) b:Pop() end)
op(bc.Syscall, function(b) b:Syscall() end)
op(bc.Jmp, function(b) b:SetPc(Arg(0)) end)
op(bc.Jif, function(b)
	b:If(Truthy(b:Pop()), function(b) b:SetPc(Arg(0)) end)
end)
op(bc.JifNot, function(b)
	b:IfNot(Truthy(b:Pop()), function(b) b:SetPc(Arg(0)) end)
end)
op(bc.JifOrPop, function(b)
	b:If(Truthy(b:Peek()),
		function(b) b:SetPc(Arg(0)) end,
		function(b) b:Pop() end)
end)
op(bc.JifNotOrPop, function(b)
	b:If(Truthy(b:Peek()),
		function(b) b:Pop() end,
		function(b) b:SetPc(Arg(0)) end)
end)
op(bc.LoadFunc, function(b) b:Push(b:MakeClosure(LoadConst(Arg(1)), Arg(0))) end)
op(bc.LoadVarg, function(b) b:VargPushN(Arg(0)) end)
op(bc.AppendVarg, function(b) b:AppendVarg(Arg(0)) end)
op(bc.VargCount, function(b) b:Push(b:IntObjFromInt(b:VargCount())) end)
op(bc.Append, function(b) b:AppendN(Arg(0)) end)
op(bc.Call, function(b) b:CallChain('norm', false) end)
op(bc.CallVarg, function(b) b:CallChain('norm', true) end)
op(bc.AppendCall, function(b) b:CallChain('push', false) end)
op(bc.AppendCallVarg, function(b) b:CallChain('push', true) end)
op(bc.Return, function(b) b:Ret() end)
op(bc.ReturnVarg, function(b)
	b:VargPush()
	b:Ret()
end)
-- No tail calls yet: bcgen emits Call keeping all results, then Return
op(bc.ReturnCall, function(b) b:Error() end)
op(bc.ReturnCallVarg, function(b) b:Error() end)

-- Call metamethod h with args if there is one, else raise a kind error about the args
local function MetaOr(b, h, callty, kind, ...)
	local args = table.pack(...)
	b:If(Truthy(h),
		function(b) b:CallMeta(callty, h, table.unpack(args, 1, args.n)) end,
		function(b) b:Error(kind, table.unpack(args, 1, args.n)) end)
end
op(bc.Not, function(b)
	b:Push(Select(Truthy(b:Pop()), False(), True()))
end)

op(bc.Len, function(b)
	local a = b:Pop()
	b:Typeck({a}, {
		{types.str, function(b, s) b:Push(b:IntObjFromInt(LoadStrLen(s))) end},
	}, function(b)
		local h = b:MetaGet(a, Str('__len'))
		b:If(Truthy(h),
			function(b) b:CallMeta('norm', h, a) end,
			function(b)
				b:Typeck({a}, {
					{types.tbl, function(b, t) b:Push(b:IntObjFromInt(b:LoadTblLen(t))) end},
				}, function(b) b:Error('len', a) end)
			end)
	end)
end)

op(bc.Neg, function(b)
	local a = b:Pop()
	b:Typeck({a}, {
		{types.int, function(b, a) b:Push(NumObj(b, Negate(LoadInt(a)))) end},
		{types.float, function(b, a) b:Push(NumObj(b, Negate(LoadFlt(a)))) end},
	}, function(b)
		MetaOr(b, b:MetaGet(a, Str('__unm')), 'norm', 'arith', a, a)
	end)
end)

op(bc.TblNew, function(b) b:Push(b:NewTbl()) end)
-- Table stays on the stack, constructors keep adding to it
op(bc.TblAdd, function(b)
	local v = b:Pop()
	local k = b:Pop()
	-- always the table from TblNew
	local t = As(b:Peek(), 'tbl')
	b:TblSet(t, k, v)
end)
op(bc.TblSet, function(b)
	local k = b:Pop()
	local t = b:Pop()
	local v = b:Pop()
	local function walk(b)
		local h = b:NewIdxWalk(t, k, v)
		b:If(Truthy(h), function(b) b:CallMeta('none', h, b:IdxSelf(), k, v) end)
	end
	-- non tables need a __newindex
	b:Typeck({t}, {
		{types.tbl, walk},
	}, function(b)
		b:If(Truthy(b:MetaGet(t, Str('__newindex'))), walk, function(b) b:Error('index', t, k) end)
	end)
end)

op(bc.CmpEq, function(b)
	local y = b:Pop() -- top of stack is right operand
	local x = b:Pop()
	b:If(ObjMetalessEq(x, y),
		function(b) b:Push(True()) end,
		function(b)
			b:If(And(IsTbl(x), IsTbl(y)),
				function(b)
					local h = b:BinMeta(x, y, Str('__eq'))
					b:If(Truthy(h),
						function(b) b:CallMeta('bool', h, x, y) end,
						function(b) b:Push(False()) end)
				end,
				function(b) b:Push(False()) end)
		end)
end)

local function PushBool(b, c)
	b:Push(Select(c, True(), False()))
end
local function cmpop(code, cmp, metamethod, swap)
	op(code, function(b)
		local y = b:Pop() -- top of stack is right operand
		local x = b:Pop()
		b:Typeck({x, y}, {
			{types.int, types.int, function(b, x, y)
				PushBool(b, cmp(LoadInt(x), LoadInt(y)))
			end},
			{types.float, types.float, function(b, x, y)
				PushBool(b, cmp(LoadFlt(x), LoadFlt(y)))
			end},
			{types.str, types.str, function(b, x, y)
				PushBool(b, cmp(StrCmp(x, y), Int(0)))
			end},
			{types.int, types.float, function(b, x, y)
				PushBool(b, cmp(Int64Flt(LoadInt(x)), LoadFlt(y)))
			end},
			{types.float, types.int, function(b, x, y)
				PushBool(b, cmp(LoadFlt(x), Int64Flt(LoadInt(y))))
			end},
		}, function(b)
			if swap then
				MetaOr(b, b:BinMeta(y, x, Str(metamethod)), 'bool', 'compare', y, x)
			else
				MetaOr(b, b:BinMeta(x, y, Str(metamethod)), 'bool', 'compare', x, y)
			end
		end)
	end)
end
cmpop(bc.CmpLe, Le, '__le')
cmpop(bc.CmpLt, Lt, '__lt')
cmpop(bc.CmpGe, Ge, '__le', true)
cmpop(bc.CmpGt, Gt, '__lt', true)

local function binmathop(code, floatlogic, intlogic, metamethod)
	op(code, function(b)
		local y = b:Pop() -- top of stack is right operand
		local x = b:Pop()
		b:Typeck({x, y}, {
			{types.int, types.int, function(b, x, y)
				b:Push(NumObj(b, intlogic(LoadInt(x), LoadInt(y))))
			end},
			{types.float, types.float, function(b, x, y)
				b:Push(NumObj(b, floatlogic(LoadFlt(x), LoadFlt(y))))
			end},
			{types.int, types.float, function(b, x, y)
				b:Push(NumObj(b, floatlogic(Int64Flt(LoadInt(x)), LoadFlt(y))))
			end},
			{types.float, types.int, function(b, x, y)
				b:Push(NumObj(b, floatlogic(LoadFlt(x), Int64Flt(LoadInt(y)))))
			end},
		}, function(b)
			MetaOr(b, b:BinMeta(x, y, Str(metamethod)), 'norm', 'arith', x, y)
		end)
	end)
end
local function binmathop_mono(code, mop, metamethod)
	return binmathop(code, mop, mop, metamethod)
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
local function binbitop(code, mop, metamethod)
	op(code, function(b)
		local y = b:Pop() -- top of stack is right operand
		local x = b:Pop()
		-- TODO assert floats are integer compatible
		b:Typeck({x, y}, {
			{types.int, types.int, function(b, x, y)
				b:Push(NumObj(b, mop(LoadInt(x), LoadInt(y))))
			end},
			{types.float, types.float, function(b, x, y)
				b:Push(NumObj(b, mop(Flt64Int(LoadFlt(x)), Flt64Int(LoadFlt(y)))))
			end},
			{types.int, types.float, function(b, x, y)
				b:Push(NumObj(b, mop(LoadInt(x), Flt64Int(LoadFlt(y)))))
			end},
			{types.float, types.int, function(b, x, y)
				b:Push(NumObj(b, mop(Flt64Int(LoadFlt(x)), LoadInt(y))))
			end},
		}, function(b)
			MetaOr(b, b:BinMeta(x, y, Str(metamethod)), 'norm', 'bitwise', x, y)
		end)
	end)
end
binbitop(bc.BAnd, BAnd, '__band')
binbitop(bc.BOr, BOr, '__bor')
binbitop(bc.BXor, BXor, '__bxor')
binbitop(bc.Shr, Shr, '__shr')
binbitop(bc.Shl, Shl, '__shl')
op(bc.BNot, function(b)
	local a = b:Pop()
	b:Typeck({a}, {
		{types.int, function(b, a)
			b:Push(NumObj(b, BXor(LoadInt(a), Int64(-1))))
		end},
		{types.float, function(b, a)
			b:Push(NumObj(b, BXor(Flt64Int(LoadFlt(a)), Int64(-1))))
		end},
	}, function(b)
		MetaOr(b, b:MetaGet(a, Str('__bnot')), 'norm', 'bitwise', a, a)
	end)
end)

op(bc.Concat, function(b)
	local y = b:Pop()
	local x = b:Pop()
	-- strings & numbers concat directly, numbers turn into strings first
	local function asstr(b, v)
		if out(v) == 'str' then
			return v
		end
		return b:ToString(v)
	end
	local cases = {}
	local strnum = {types.str, types.int, types.float}
	for _, tx in ipairs(strnum) do
		for _, ty in ipairs(strnum) do
			cases[#cases+1] = {tx, ty, function(b, x, y)
				b:Push(b:StrConcat(asstr(b, x), asstr(b, y)))
			end}
		end
	end
	b:Typeck({x, y}, cases, function(b)
		MetaOr(b, b:BinMeta(x, y, Str('__concat')), 'norm', 'concat', x, y)
	end)
end)

op(bc.Idx, function(b)
	local k = b:Pop()
	local t = b:Pop()
	-- only tables, vecs & values with an __index can be indexed
	b:IfNot(IsTblOrVec(t), function(b)
		b:IfNot(Truthy(b:MetaGet(t, Str('__index'))), function(b) b:Error('index', t, k) end)
	end)
	local v = b:IdxWalk(t, k)
	local recv = b:IdxSelf()
	b:If(Truthy(recv),
		function(b) b:CallMeta('norm', v, recv, k) end,
		function(b) b:Push(v) end)
end)

return {
	mops = mops,
	ops = ops,
	broken = broken,
	walk = walk,
}

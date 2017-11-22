local lex = require 'lex'
local ast = require 'ast'
local bc = require 'bc'

local function nop()
end

local asmmeta = {}
local asmmt = { __index = asmeta }
local function Assembler(lx, uplink)
	return setmetatable({
		lx = lx,
		pcount = 0,
		isdotdotdot = false,
		uplink = uplink,
		scopes = nil,
		breaks = nil,
		consts = {},
		labels = {},
		gotos = {},
		funcs = {},
		namety = {},
		rconsts = {
			integer = {},
			float = {},
			string = {},
		},
		names = {},
		bc = {},
	}, asmmt)
end

function asmmeta:push(op, ...)
	self.bc[#self.bc+1] = op
	for i=1,select('#', ...) do
		self:patch(#self.bc+1, select(i, ...))
	end
end
function asmmeta:patch(idx, x)
	self.bc[idx],self.bc[idx+1],self.bc[idx+2],self.bc[idx+3] = string.byte(string.pack('<i4', x), 1, 4)
end
function asmmeta:breakscope(f)
	self.breaks = { prev = self.breaks }
	f(self)
	for i=1,#self.breaks do
		self:patch(self.breaks[i], #self.bc)
	end
	self.breaks = self.breaks.prev
end
function asmmeta:scope(f)
	self.scopes = { prev = self.scopes }
	f(self)
	for i=1, #self.scopes do
		local name = self.scopes[i]
		self.names[name] = self.names[name].prev
	end
	self.scopes = self.scopes.prev
end
function asmmeta:const(c)
	local ty = math.type(c) or type(c)
	local n = self.rconsts[ty][c]
	if not n then
		n = #self.consts+1
		self.consts[n] = c
		self.rconsts[ty][c] = n
	end
	return n
end

function asmmeta:name(n)
	local prevscope = self.names[n]
	local newscope = { prev = prevscope, func = self }
	self.scopes[#self.scopes+1] = n
	self.names[n] = newscope
end

function asmmeta:usename(node)
	local name = self.names[node:int()]
	if name then
		self.namety[node] = name
	else
		name = self.names[1]
	end
	if name.func ~= self then
		if name.free then
			name.free[self] = true
		else
			name.free = { [self] = true }
		end
	end
end

local nextNode = {}
for k,v in pairs(ast) do
	nextNode[v] = function(node, i)
		while i > 0 do
			local child = node.fathered[i]
			i = i - 1
			if (child.type & 31) == ty then
				return i, child
			end
		end
	end
end

local function hasToken(node, tok)
	for i=#node.fathered, 1, -1 do
		local child = node.fathered[i]
		if child.type == -1 and child:val() == ty then
			return true
		end
	end
	return false
end

local function nextMask(ty)
	return function(node, i)
		while i > 0 do
			local child = node.fathered[i]
			i = i - 1
			if child.type == -1 and child:val() == ty then
				return i, child
			end
		end
	end
end
local nextString = nextMask(lex._string)
local nextNumber = nextMask(lex._number)
local nextIdent = nextMask(lex._ident)

local function selectNodes(node, ty)
	return nextNode[ty], node, #node.fathered
end
local function selectNode(node, ty)
	return nextNode[ty](node, #node.fathered)
end

local function selectIdents(node)
	return nextIdent, node, #node.fathered
end
local function selectIdent(node)
	return nextIdent(node, #node.fathered)
end

local unOps = { bc.Neg, bc.Not, bc.Len, bc.BNot }
local binOps = { bc.Add, bc.Sub, bc.Mul, bc.Div, bc.IDiv, bc.Pow, bc.Mod,
	bc.BAnd, bc.BXor, bc.BOr, bc.Shr, bc.Shl, bc.Concat,
	bc.CmpLt, bc.CmpLe, bc.CmpGt, bc.CmpGe, bc.CmpEq }
local scopeStatSwitch, emitStatSwitch, emitValueSwitch, emitFieldSwitch, visitScope, emitScope

local function singleNode(self, node, ty, visit, ...)
	local sn = selectNode(node, ty)
	if sn then
		return visit[ty](self, sn, ...)
	end
end
local function multiNodes(self, node, ty, visit, ...)
	local fn = visit[ty]
	for i, node in selectNodes(node, ty) do
		fn(self, node, ...)
	end
end
local function scopeNode(self, node, ty)
	return singleNode(self, node, ty, visitScope)
end
local function emitNode(self, node, ty, ...)
	return singleNode(self, node, ty, visitEmit, ...)
end
local function scopeNodes(self, node, ty)
	return multiNodes(self, node, ty, visitScope)
end
local function emitNodes(self, node, ty, ...)
	return multiNodes(self, node, ty, visitEmit, ...)
end

local Exp32 = ast.Exp|32
local precedenceTable = {7, 7, 8, 8, 8, 9, 8, 5, 4, 3, 6, 6, 2, 1, 1, 1, 1, 1, 1}
local function precedence(node)
	if (node.type&31) == ast.Binop then
		return precedenceTable[x.type >> 5]
	else
		return 0
	end
end
local function shunt(node)
	return coroutine.wrap(function()
		local ops = {}
		while node.type == Exp32 and node.fathered.length == 3 do
			local rson, op, lson = table.unpack(node.fathered)
			coroutine.yield(lson)
			while true do
				if #ops == 0 then
					break
				end
				local oprec = precedence(op)
				if precedence(ops[#ops]) < precedence(op) and precedence(op) == 9 then
					break
				end
				coroutine.yield(ops[#ops])
				ops[#ops] = nil
			end
			ops[#ops+1] = op
			node = rson
		end
		if node.type == Exp32 then
			coroutine.yield(selectNode(node, ast.Value))
		else
			coroutine.yield(node)
		end
		coroutine.yield()
		for i=#ops, 1, -1 do
			coroutine.yield(ops[i])
		end
	end)
end

scopeStatSwitch = {
	nop, -- 1 ;
	function(self, node) -- 2 vars=exps
		scopeNodes(self, node, ast.ExpOr)
		scopeNodes(self, node, ast.Var)
	end,
	function(self, node) -- 3 call
		scopeNode(self, node, ast.Functioncall)
	end,
	nop, -- 4 label
	nop, -- 5 break
	nop, -- 6 goto
	function(self, node) -- 7 do-end
		self:scope(function()
			scopeNode(self, node, ast.Block)
		end)
	end,
	function(self, node) -- 8 while
		self:scope(function()
			scopeNode(self, node, ast.ExpOr)
			scopeNode(self, node, ast.Block)
		end)
	end,
	function(self, node) -- 9 repeat
		self:scope(function()
			scopeNode(self, node, ast.Block)
			scopeNode(self, node, ast.ExpOr)
		end)
	end,
	function(self, node) -- 10 if
		scopeNodes(self, node, ast.ExpOr)
		for i, block in selectNodes(node, ast.Block) do
			self:scope(function()
				visitScope[ty](self, block)
			end)
		end
	end,
	function(self, node) -- 11 for
		scopeNodes(self, node, ast.ExpOr)
		local name = selectIdent(node)
		self:name(name:int())
		scopeNode(self, node, ast.Block)
	end,
	function(self, node) -- 12 generic for
		scopeNodes(self, node, ast.ExpOr)
		for i, name in selectIdents(node) do
			self:name(name:int())
		end
		scopeNode(self, node, ast.Block)
	end,
	function(self, node) -- 13 func
		local clasm = Assembler(self.lx, self)
		local fruit = selectNode(node, ast.Funcbody)
		self:usename(selectIdent(node))
		visitScope[ast.Funcbody](clasm, fruit)
	end,
	function(self, node) -- 14 self:func
		local clasm = Assembler(self.lx, self)
		local fruit = selectNode(node, ast.Funcbody)
		self:usename(selectIdent(node))
		clasm:name(2)
		visitScope[ast.Funcbody](clasm, fruit, true)
	end,
	function(self, node) -- 15 local func
		local clasm = Assembler(self.lx, self)
		local fruit = selectNode(node, ast.Funcbody)
		local name = selectIdent(node)
		self:name(name:int())
		visitScope[ast.Funcbody](clasm, fruit)
	end,
	function(self, node) -- 16 locals=exps
		scopeNodes(self, node, ast.ExpOr)
		for i, name in selectIdents(node) do
			self:name(name:int())
		end
	end,
}
local function emitCall(self, node, outputs)
	local methname = selectIdent(node)
	if methname then
		self:push(bc.LoadConst, self:const(self.lx.ssr[methname:int()]))
		self:push(bc.LoadMeth)
	end
	return emitNode(self, node, ast.Args, outputs)
end
local function emitFunccall(self, node, outputs)
	emitNode(self, node, ast.Prefix)
	emitNodes(self, node, ast.Suffix)
	return emitCall(self, node, outputs)
end
local function emitExplist(self, node, outputs)
	local lastv
	for i, v in selectNodes(node, ast.ExpOr) do
		if lastv then
			if outputs == 0 then
				visitEmit[ast.ExpOr](self, lastv, 0)
			else
				if outputs ~= -1 then
					outputs = outputs - 1
				end
				visitEmit[ast.ExpOr](self, lastv, 1)
			end
		end
		lastv = v
	end
	return visitEmit[ast.ExpOr](self, lastv, outputs)
end
emitStatSwitch = {
	nop, -- 1 ;
	function(self, node) -- 2 vars=exps
		local vars = {}
		for i, v in selectNodes(node, ast.Var) do
			vars[#vars+1] = v
		end
		emitExplist(self, node, #vars)
		-- TODO evaluate in order
		for i=#vars,1,-1 do
			visitEmit[ast.Var](self, vars[i], false)
		end
	end,
	function(self, node) -- 3 call
		return emitFunccall(self, node, 0)
	end,
	function(self, node) -- 4 label
		local name = selectIdent(node)
		self.labels[name:int()] = #self.bc
	end,
	function(self, node) -- 5 break
		assert(self.breaks, "break outside of loop")
		self.breaks[#self.breaks+1] = #self.bc+1
		self.push(bc.Goto, 0)
	end,
	function(self, node) -- 6 goto
		local name = selectIdent(node)
		self.gotos[#self.bc+1] = name:int()
		self.push(bc.Goto, 0)
	end,
	function(self, node) -- 7 do-end
		return emitNode(self, node, ast.Block)
	end,
	function(self, node) -- 8 while
		self:breakscope(function()
			local soc = #self.bc
			emitNode(self, node, ast.ExpOr, 1)
			local jmp = #self.bc+1
			self:push(bc.JifNot, 0)
			emitNode(self, node, ast.Block)
			self:push(bc.Jmp, soc)
			self:patch(jmp, #self.bc)
		end)
	end,
	function(self, node) -- 9 repeat
		self:breakscope(function()
			local soc = #self.bc
			emitNode(self, node, ast.Block)
			emitNode(self, node, ast.ExpOr, 1)
			self:push(bc.JifNot, soc)
		end)
	end,
	function(self, node) -- 10 if
		local eob, condbr = {}
		for i=#node.fathered, 1, -1 do
			local child = node.fathered[i]
			local ty = child.type&31
			if ty == ast.ExpOr then
				emitNode(self, node, ast.ExpOr, 1)
				condbr = #self.bc+1
				self:push(bc.JifNot, 0)
			elseif ty == ast.Block then
				emitNode(self, node, ast.Block)
				if i > 2 then
					eob[#eob+1] = #self.bc+1
					emitNode(bc.Jmp, 0)
				end
				if condbr then
					self:patch(condbr, #self.bc)
					condbr = nil
				end
			end
		end
		for i=1,#eob do
			self:patch(eob[i], #self.bc)
		end
	end,
	function(self, node) -- 11 for
		local exps=0
		for i, n in selectNodes(node, ast.ExpOr) do
			visitEmit[ast.ExpOr](self, n, 1)
			exps = exps+1
		end
		if exps == 2 then
			self:push(bc.LoadConst, 1)
		end
		-- TODO bind variables, loop
		visitEmit[ast.Block](self, node, ast.Block)
	end,
	function(self, node) -- 12 generic for
		visitExplist(self, node, 3)
		-- TODO bind variables, loop
		visitEmit[ast.Block](self, node, ast.Block)
	end,
	function(self, node) -- 13 func
		visitEmit[ast.Funcbody](self, node, ast.Funcbody)
		local first, nlast = true
		for i, name in selectIdents(node) do
			if nlast then
				if first then
					self:loadname(nlast)
					first = false
				else
					self:push(bc.LoadConst, self:const(self.ssr[nlast]))
					self:push(bc.TblGet)
				end
			end
			nlast = name:int()
		end
		if first then
			self:storename(nlast)
		else
			self:push(bc.LoadConst, self:const(self.ssr[nlast]))
			self:push(bc.TblSet)
		end
	end,
	function(self, node) -- 14 self:func
		visitEmit[ast.Funcbody](self, node, ast.Funcbody)
		-- TODO inject self, codegen
	end,
	function(self, node) -- 15 local func
		visitEmit[ast.Funcbody](self, node, ast.Funcbody)
		local name = selectIdent(node)
		self:storename(name:int())
	end,
	function(self, node) -- 16 locals=exps
		-- TODO scope resolving
		local vars = {}
		for i, v in selectIdents(node) do
			vars[#vars+1] = v:int()
		end
		emitExplist(self, node, #vars)
		for i=#vars,1,-1 do
			self:storename(vars[i])
		end
	end,
}
local function emit0(self, node, outputs, fn)
	if outputs == 0 then
		return 0
	else
		return fn(self, node, outputs)
	end
end
emitValueSwitch = {
	function(self, node, outputs) -- 1 nil
		return emit0(self, node, outputs, function(self, node)
			self:push(bc.LoadNil)
			return 1
		end)
	end,
	function(self, node, outputs) -- 2 false
		return emit0(self, node, outputs, function(self, node)
			self:push(bc.LoadFalse)
			return 1
		end)
	end,
	function(self, node, outputs) -- 3 true
		return emit0(self, node, outputs, function(self, node)
			self:push(bc.LoadTrue)
			return 1
		end)
	end,
	function(self, node, outputs) -- 3 num
		return emit0(self, node, outputs, function(self, node)
			local val = nextNumber(node, #node.fathered)
			self:push(bc.LoadConst, self:const(self.lx.snr[val:int()]))
			return 1
		end)
	end,
	function(self, node, outputs) -- 4 str
		return emit0(self, node, outputs, function(self, node)
			local val = nextString(node, #node.fathered)
			self:push(bc.LoadConst, self:const(self.lx.ssr[val:int()]))
			return 1
		end)
	end,
	function(self, node, outputs) -- 5 ...
		return emit0(self, node, outputs, function(self, node)
			self:push(bc.LoadVarg, outputs)
			return outputs
		end)
	end,
	function(self, node, outputs) -- 6 Funcbody
		return emit0(self, node, outputs, function(self, node)
			emitNode(self, node, Funcbody)
			return 1
		end)
	end,
	function(self, node, outputs) -- 7 Table
		emitNode(self, node, ast.Table)
		return 1
	end,
	function(self, node, outputs) -- 8 Call
		return emitFunccall(self, node, outputs)
	end,
	function(self, node, outputs) -- 9 Var load
		emitNode(self, node, ast.Var, true)
		return 1
	end,
	function(self, node, outputs) -- 10 Exp
		emitNode(self, node, ast.ExpOr, 1)
		return 1
	end,
}
emitFieldSwitch = {
	function(self, node) -- 1 [exp] = exp
		local f, obj, idx = selectNodes(node, ast.ExpOr)
		local i, key = f(obj, idx)
		visitEmit[ast.ExpOr](self, key, 1)
		local _i, val = f(obj, i)
		visitEmit[ast.ExpOr](self, val, 1)
		self:push(bc.TblAdd)
	end,
	function(self, node) -- 2 name = exp
		local val = nextString(node, #node.fathered)
		self:push(bc.LoadConst, self:const(self.lx.ssr[val:int()]))
		emitNode(self, node, ast.ExpOr)
		self:push(bc.TblAdd)
	end,
	function(self, node) -- 3 exp
		-- TODO need to defer these to end, also group num
		local n = 0 -- TODO incr n
		self:push(bc.LoadConst, self:const(n))
		emitNode(self, node, ast.ExpOr)
		self:push(bc.TblAdd)
	end
}
visitScope = {
	[ast.Block] = function(self, node)
		scopeNodes(self, node, ast.Stat)
		scopeNodes(self, node, ast.ExpOr)
	end,
	[ast.Stat] = function(self, node)
		return scopeStatSwitch[node.type >> 5](self, node)
	end,
	[ast.Var] = function(self, node)
		if node.types >> 5 == 0 then
			self:usename(selectIdent(node))
		else
			scopeNode(self, node, ast.Prefix)
			scopeNode(self, node, ast.Index)
		end
	end,
	[ast.Exp] = function(self, node)
		if #node.fathered == 1 then
			assert(self.fathered[1].type == ast.Value)
			return visitScope[ast.Value](self.fathered[1], node)
		elseif node.type >> 5 == 0 then
			return scopeNodes(self, node, ast.Exp)
		else
			for i = #node.fathered, 1, -1 do
				local n = node.fathered[i]
				local nt = n.type & 31
				if nt == ast.Exp then
					visitScope[ast.Exp](self, node)
				elseif nt == ast.Value then
					visitScope[ast.Value](self, node)
				end
			end
		end
	end,
	[ast.Prefix] = function(self, node)
		if node.type >> 5 == 0 then
			self:usename(selectIdent(node))
		else
			scopeNode(self, node, ast.ExpOr)
		end
	end,
	[ast.Args] = function(self, node)
		local t = node.type >> 5
		if t == 0 then
			scopeNodes(self, node, ast.ExpOr)
		elseif t == 1 then
			scopeNode(self, node, ast.Table)
		end
	end,
	[ast.Funcbody] = function(self, node, isMeth)
		local isdotdotdot = hasToken(node, lex._dotdotdot)
		local names = {selectIdents(node)}
		local pcount = #names
		if isMeth then
			pcount = pcount + 1
		end
		local asm = Assembler(lx, self)
		asm.isdotdotdot = isdotdotdot
		asm.pcount = pcount
		asm:scope(function()
			if isMeth then
				asm:name(2)
			end
			for i=1,#names do
				asm:name(names[i]:int())
			end
			scopeNode(asm, ast.Block)
		end)
		emitNode(asm, ast.Block)
		asm:push(bc.Return)
		self.funcs[node] = {} -- TODO args for LoadFunc
	end,
	[ast.Table] = function(self, node)
		scopeNodes(self, node, ast.Field)
	end,
	[ast.Field] = function(self, node)
		scopeNodes(self, node, ast.ExpOr)
	end,
	[ast.Binop] = nop,
	[ast.Unop] = nop,
	[ast.Value] = function(self, node)
		local t = node.type >> 5
		-- TODO if t == 5 then assert(self.isdotdotdot)
		if t == 7 then
			scopeNode(self, node, ast.Funcbody)
		elseif t == 8 then
			scopeNode(self, node, ast.Table)
		elseif t == 9 then
			scopeNode(self, node, ast.Prefix)
			scopeNode(self, node, ast.Args)
		elseif t == 10 then
			scopeNode(self, node, ast.Var)
		elseif t == 11 then
			scopeNode(self, node, ast.ExpOr)
		end
	end,
	[ast.Index] = function(self, node)
		if node.type >> 5 == 0 then
			scopeNode(self, node, ast.ExpOr)
		end
	end,
	[ast.Suffix] = function(self, node)
		if node.type >> 5 == 0 then
			scopeNode(self, node, ast.Args)
		else
			scopeNode(self, node, ast.Index)
		end
	end,
	[ast.ExpOr] = function(self, node)
		return scopeNodes(self, node, ast.ExpAnd)
	end,
	[ast.ExpAnd] = function(self, node)
		return scopeNodes(self, node, ast.Exp)
	end,
}
local function emitShortCircuitFactory(ty, opcode)
	return function(self, node, out)
		local prod
		if #node.fathered == 1 then
			prod = visitEmit[ty](self, node.fathered[1], out)
		else
			for i, n in selectNode(node, ty) do
				visitEmit[ty](self, n, 1)
				if lab then
					self:patch(lab, #self.bc)
				end
				if i > 1 then
					lab = #self.bc+1
					self:push(opcode, 0)
				end
			end
			prod = 1
		end
		for i=prod+1, out do
			self:push(bc.Pop)
		end
		for i=prod-1, out, -1 do
			self:push(bc.LoadNil)
		end
		return out
	end
end
visitEmit = {
	[ast.Block] = function(self, node)
		emitNodes(self, node, ast.Stat)
		if hasToken(node, lex._return) then
			emitExplist(self, node, -1)
			-- TODO RETURN
		end
	end,
	[ast.Stat] = function(self, node)
		return emitStatSwitch[node.type >> 5](self, node)
	end,
	[ast.Var] = function(self, node, isload)
		if self.type >> 5 == 0 then
			local name = selectIdent(node):int()
			if isload then
				self:loadname(name)
			else
				self:storename(name)
			end
		else
			emitNode(self, node, ast.Prefix)
			emitNodes(self, node, ast.Suffix)
			return emitNode(self, node, ast.Index, isload)
		end
	end,
	[ast.Exp] = function(self, node, out)
		if node.type >> 5 == 0 then
			emitNode(self, node, ast.Exp, 1)
			emitNode(self, node, ast.Unop)
			return 1
		else
			if #node.fathered == 1 then
				return visitEmit[ast.Value](self, node.fathered[1], out)
			else
				for op in shunt(node) do
					local ty = op.type & 31
					if ty == ast.Binop then
						visitEmit[ast.Binop](self, op)
					elseif ty == ast.Value then
						visitEmit[ast.Value](self, op, 1)
					else
						assert(op.type >> 5 == 0)
						visitEmit[ast.Exp](self, op, 1)
					end
				end
			end
		end
	end,
	[ast.Prefix] = function(self, node)
		if self.type >> 5 == 0 then
			self:loadname(selectIdent(node):int())
		else
			emitNode(self, node, ast.ExpOr, 1)
		end
	end,
	[ast.Args] = function(self, node, outputs)
		-- TODO we need to either mark exp-depth for varcall or implement call chaining
		local ty, n = node.type >> 5
		if ty == 0 then
			emitExplist(self, node, -1)
			n = -1
		elseif ty == 1 then
			self:push(bc.TblNew)
			emitNodes(self, node, ast.Field)
			n = 1
		else
			self:push(bc.LoadConst, self:const(self.lx.ssr[val:int()]))
			n = 1
		end
		-- TODO RetCall
		self:push(bc.Call)
	end,
	[ast.Funcbody] = function(self, node)
		self:push(bc.LoadFunc, table.unpack(self.funcs[node]))
	end,
	[ast.Table] = function(self, node)
		self:push(bc.TblNew)
		return emitNodes(self, node, ast.Field)
	end,
	[ast.Field] = function(self, node)
		return emitFieldSwitch[node.type >> 5](self, node)
	end,
	[ast.Binop] = function(self, node)
		local op = binOps[node.type >> 5]
		if op then
			self:push(op)
		else
			self:push(bc.CmpEq)
			self:push(bc.Not)
		end
	end,
	[ast.Unop] = function(self, node)
		self:push(unaryOps[node.type >> 5])
	end,
	[ast.Value] = function(self, node, outputs)
		local results = emitValueSwitch[self.type >> 5](self, node, outputs)
		for i=results+1, outputs do
			self:push(bc.Pop)
		end
	end,
	[ast.Index] = function(self, node, isload)
		if node.type >> 5 == 0 then
			emitNode(self, node, ast.ExpOr, 1)
		else
			self:push(bc.LoadConst, self:const(self.lx.ssr[selectIdent(node):int()]))
		end
		if isload then
			self:push(bc.Idx)
		else
			self:push(bc.TblSet)
		end
	end,
	[ast.Suffix] = function(self, node)
		if node.type >> 5 == 0 then
			return emitCall(self, node, 1)
		else
			return emitNode(self, node, ast.Index, true)
		end
	end,
	[ast.ExpOr] = emitShortCircuitFactory(ast.ExpAnd, bc.JifOrPop),
	[ast.ExpAnd] = emitShortCircuitFactory(ast.Exp, bc.JifNotOrPop),
}

function asmmeta:synth()
	for k,v in pairs(self.gotos) do
		self:patch(k, self.labels[v])
	end
end

return function(lx, root)
	local asm = Assembler(lx, nil)
	asm.pcount = 1
	asm.isdotdotdot = true
	asm:scope(function()
		asm:name(1) -- _ENV
		visitScope[ast.Block](asm, root)
	end)
	visitEmit[ast.Block](asm, root)
	asm:push(bc.Return)
	return asm.synth()
end
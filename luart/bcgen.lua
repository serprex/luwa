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
		rconsts = {
			integer = {},
			float = {},
			string = {},
		},
		names = {},
		idxfree = {},
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

function asmmeta:name(n, idx)
	local prevscope = self.names[n]
	local newscope = { prev = prevscope, idx = idx, func = self }
	self.scopes[#self.scopes+1] = n
	self.names[n] = newscope
end

function asmmeta:usename(n)
	local name = self.names[n]
	if name then
		if name.func ~= self then
			self.idxfree[name.idx] = true
		end
	else
		return asmmeta:usename(1) -- _ENV
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
		self:name(name:int(), name.li)
		scopeNode(self, node, ast.Block)
	end,
	function(self, node) -- 12 generic for
		scopeNodes(self, node, ast.ExpOr)
		for i, name in selectIdents(node) do
			self:name(name:int(), name.li)
		end
		scopeNode(self, node, ast.Block)
	end,
	function(self, node) -- 13 func
		local clasm = Assembler(self.lx, self)
		local fruit = selectNode(node, ast.Funcbody)
		self:usename(selectIdent(node):int())
		visitScope[ast.Funcbody](clasm, fruit)
		visitEmit[ast.Funcbody](clasm, fruit)
	end,
	function(self, node) -- 14 self:func
		local clasm = Assembler(self.lx, self)
		local fruit = selectNode(node, ast.Funcbody)
		self:usename(selectIdent(node):int())
		clasm:name(2, -2)
		visitScope[ast.Funcbody](clasm, fruit)
		visitEmit[ast.Funcbody](clasm, fruit)
	end,
	function(self, node) -- 15 local func
		local clasm = Assembler(self.lx, self)
		local fruit = selectNode(node, ast.Funcbody)
		local name = selectIdent(node)
		self:name(name:int(), name.li)
		visitScope[ast.Funcbody](clasm, fruit)
		visitEmit[ast.Funcbody](clasm, fruit)
	end,
	function(self, node) -- 16 locals=exps
		scopeNodes(self, node, ast.ExpOr)
		for i, name in selectIdents(node) do
			self:name(name:int(), name.li)
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
emitStatSwitch = {
	nop, -- 1 ;
	function(self, node) -- 2 vars=exps
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
	end,
	function(self, node) -- 12 generic for
	end,
	function(self, node) -- 13 func
	end,
	function(self, node) -- 14 self:func
	end,
	function(self, node) -- 15 local func
	end,
	function(self, node) -- 16 locals=exps
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
		visitEmit[ast.ExpOr](self, key)
		local _i, val = f(obj, i)
		visitEmit[ast.ExpOr](self, val)
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
			self:usename(selectIdent(node):int())
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
			self:usename(selectIdent(node):int())
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
	[ast.Funcbody] = function(self, node)
		-- TODO ahhh
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
	return function(self, node, ...)
		if #node.fathered == 1 then
			visitEmit[ty](self, node.fathered[1], ...)
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
		end
	end
end
visitEmit = {
	[ast.Block] = function(self, node)
		emitNodes(self, node, ast.Stat)
		if hasToken(node, lex._return) then
			emitNodes(self, node, ast.ExpOr)
			-- TODO RETURN
		end
	end,
	[ast.Stat] = function(self, node)
		return emitStatSwitch[node.type >> 5](self, node)
	end,
	[ast.Var] = function(self, node, isload)
	end,
	[ast.Exp] = function(self, node)
	end,
	[ast.Prefix] = function(self, node)
	end,
	[ast.Args] = function(self, node)
	end,
	[ast.Funcbody] = function(self, node)
	end,
	[ast.Table] = function(self, node)
		self:push(bc.TblNew)
		emitNodes(self, node, ast.Field)
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
	[ast.Value] = function(self, node)
		return emitValueSwitch[self.type >> 5](self, node)
	end,
	[ast.Index] = function(self, node)
	end,
	[ast.Suffix] = function(self, node)
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
		asm:name(1, -1) -- _ENV
		visitScope[ast.Block](asm, root)
	end)
	visitEmit[ast.Block](asm, root)
	asm:push(bc.Return, 0, 0)
	return asm.synth()
end
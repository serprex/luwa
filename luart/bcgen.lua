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
		names = {},
		idxfree = {},
		bc = {},
	}, asmmt)
end

function asmmeta:push(op, ...)
	self.bc[#self.bc+1] = op
	for i=1,select('#', ...) do
		self.bc[#self.bc+1],self.bc[#self.bc+2],self.bc[#self.bc+3],self.bc[#self.bc+4] = string.pack('<i4', select(i, ...))
	end
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

local function nextNodeFactory(ty)
	return function(node, i)
		while i > 0 do
			local child = node.fathered[i]
			i = i - 1
			if (child.type & 31) == ty then
				return i, child
			end
		end
	end
end
local nextNode = {}
for k,v in pairs(ast) do
	nextNode[v] = nextNode(v)
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

local function scope(self, node)
	return visitScope[node.type](node)
end
local function scopeNode(self, node, ty)
	return visitScope[ty](self, selectNode(node, ty))
end
local function scopeNodes(self, node, ty)
	local fn = visitScope[ty]
	for i, node in selectNodes(node, ty) do
		fn(self, node)
	end
end

local scopeStatSwitch = {
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
		-- TODO usename
		scopeNode(self, node, ast.Block)
	end,
	function(self, node) -- 12 generic for
		scopeNodes(self, node, ast.ExpOr)
		-- TODO usename
		scopeNode(self, node, ast.Block)
	end,
	function(self, node) -- 13 func
		-- TODO
		local clasm = Assembler(self.lx, self)
		local fruit = selectNode(node, ast.Funcbody)
		-- TODO self:usename
		visitScope[ast.Funcbody](clasm, fruit)
		visitEmit[ast.Funcbody](clasm, fruit)
	end,
	function(self, node) -- 14 self:func
		local clasm = Assembler(self.lx, self)
		local fruit = selectNode(node, ast.Funcbody)
		-- TODO self:usename
		visitScope[ast.Funcbody](clasm, fruit)
		visitEmit[ast.Funcbody](clasm, fruit)
	end,
	function(self, node) -- 15 local func
		local clasm = Assembler(self.lx, self)
		local fruit = selectNode(node, ast.Funcbody)
		-- TODO self:name
		visitScope[ast.Funcbody](clasm, fruit)
		visitEmit[ast.Funcbody](clasm, fruit)
	end,
	function(self, node) -- 16 local vars=exps
		-- TODO name
	end,
}

local visitScope = {
	[ast.Block] = function(self, node)
		scopeNodes(self, node, ast.Stat)
		scopeNode(self, node, ast.Retstat)
	end,
	[ast.Stat] = function(self, node)
		return scopeStatSwitch[node.type >> 5](self, node)
	end,
	[ast.Retstat] = function(self, node)
		scopeNodes(self, node, ast.ExpOr)
	end,
	[ast.Label] = function(self, node)
		-- TODO how do we even
	end,
	[ast.Var] = function(self, node)
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
	end,
	[ast.Funcbody] = function(self, node)
	end,
	[ast.Tableconstructor] = function(self, node)
	end,
	[ast.Field] = function(self, node)
	end,
	[ast.Binop] = function(self, node)
	end,
	[ast.Unop] = function(self, node)
	end,
	[ast.Value] = function(self, node)
	end,
	[ast.Index] = function(self, node)
	end,
	[ast.Suffix] = function(self, node)
	end,
	[ast.ExpOr] = function(self, node)
		return scopeNodes(self, node, ast.ExpAnd)
	end,
	[ast.ExpAnd] = function(self, node)
		return scopeNodes(self, node, ast.Exp)
	end,
}
local visitEmit = {
	[ast.Block] = function(self, node)
		emitNodes(self, node, ast.Stat)
		emitNode(self, node, ast.Retstat)
	end,
	[ast.Stat] = function(self, node)
	end,
	[ast.Retstat] = function(self, node)
	end,
	[ast.Label] = function(self, node)
	end,
	[ast.Var] = function(self, node)
	end,
	[ast.Exp] = function(self, node)
	end,
	[ast.Prefix] = function(self, node)
	end,
	[ast.Args] = function(self, node)
	end,
	[ast.Funcbody] = function(self, node)
	end,
	[ast.Tableconstructor] = function(self, node)
	end,
	[ast.Field] = function(self, node)
	end,
	[ast.Binop] = function(self, node)
	end,
	[ast.Unop] = function(self, node)
	end,
	[ast.Value] = function(self, node)
	end,
	[ast.Index] = function(self, node)
	end,
	[ast.Suffix] = function(self, node)
	end,
	[ast.ExpOr] = function(self, node)
	end,
	[ast.ExpAnd] = function(self, node)
	end,
}

function asmmeta:synth()
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
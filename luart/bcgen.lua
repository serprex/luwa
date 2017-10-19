local lex = require 'lex'
local ast = require 'ast'
local bc = require 'bc'

local function nop()
end

local asmmeta = {}
local asmmt = { __index = asmeta }
local function Assembler(lx, pcount, isdotdotdot, uplink)
	return setmetatable({
		lx = lx,
		pcount = pcount,
		isdotdotdot = isdotdotdot,
		uplink = uplink,
		scopes = {},
		names = {},
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

function asmmeta:name(n, isparam)
	local prevscope = self.names[n]
	local newscope = { prev = prevscope, isparam = isparam }
	self.scopes[#self.scopes+1] = n
	self.names[n] = newscope
end

function asmmeta:usename(n)
	local name = self.names[n]
	if name then
		name.isfree = true
	else
		self.names[1].isfree = true -- _ENV
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

local function selectNodes(node, ty)
	return nextNode[ty], node, #node.fathered
end
local function selectNode(node, ty)
	return nextNode[ty](node, #node.fathered)
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

local function scopeStatLoop(self, node)
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
	end,
	function(self, node) -- 14 local func
		-- TODO
	end,
	function(self, node) -- 15 local vars=exps
		-- TODO usename
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
	[ast.Retstat] = function()
		scopeNodes(self, node, ast.ExpOr)
	end,
	[ast.Label] = function()
	end,
	[ast.Funcname] = function()
	end,
	[ast.Var] = function()
	end,
	[ast.Exp] = function()
	end,
	[ast.Prefix] = function()
	end,
	[ast.Functioncall] = function()
	end,
	[ast.Args] = function()
	end,
	[ast.Funcbody] = function()
	end,
	[ast.Tableconstructor] = function()
	end,
	[ast.Field] = function()
	end,
	[ast.Binop] = function()
	end,
	[ast.Unop] = function()
	end,
	[ast.Value] = function()
	end,
	[ast.Index] = function()
	end,
	[ast.Call] = function()
	end,
	[ast.Suffix] = function()
	end,
	[ast.ExpOr] = function()
	end,
	[ast.ExpAnd] = function()
	end,
}
local visitEmit = {
	[ast.Block] = function()
	end,
	[ast.Stat] = function()
	end,
	[ast.Retstat] = function()
	end,
	[ast.Label] = function()
	end,
	[ast.Funcname] = function()
	end,
	[ast.Var] = function()
	end,
	[ast.Exp] = function()
	end,
	[ast.Prefix] = function()
	end,
	[ast.Functioncall] = function()
	end,
	[ast.Args] = function()
	end,
	[ast.Funcbody] = function()
	end,
	[ast.Tableconstructor] = function()
	end,
	[ast.Field] = function()
	end,
	[ast.Binop] = function()
	end,
	[ast.Unop] = function()
	end,
	[ast.Value] = function()
	end,
	[ast.Index] = function()
	end,
	[ast.Call] = function()
	end,
	[ast.Suffix] = function()
	end,
	[ast.ExpOr] = function()
	end,
	[ast.ExpAnd] = function()
	end,
}

function asmmeta:genBlock(node)
end

function asmmeta:synth()
end

return function(lx, root)
	local asm = Assembler(lx, tree, true, nil)
	asm.scope(function()
		asm.name(1, true) -- _ENV
		asm.scopeBlock(root)
	end)
	asm.genBlock(root)
	asm.push(bc.Return, 0, 0)
	return asm.synth()
end
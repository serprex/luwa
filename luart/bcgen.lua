local lex = require 'lex'
local ast = require 'ast'
local bc = require 'bc'

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

function asmmeta:scopeBlock(node)
end

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
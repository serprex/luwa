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
		bc = {},
	}, asmmt)
end

function asmmeta:push(op, ...)
	self.bc[#self.bc+1] = op
	for i=1,select('#', ...) do
		self.bc[#self.bc+1],self.bc[#self.bc+2],self.bc[#self.bc+3],self.bc[#self.bc+4] = string.pack('<i4', select(i, ...))
	end
end
function asmmeta:scope()
end

function asmmeta:name()
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
		asm.name(0, -1) -- _ENV
		asm.scopeBlock(root)
	end)
	asm.genBlock(root)
	asm.push(bc.Return, 0, 0)
	return asm.synth()
end
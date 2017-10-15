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
		scopedata = {},
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
	local nsdata = #self.scopedata
	f(self)
	for i=#self.scopedata, nsdata, -1 do
		local sdata = self.scopedata
		local sname = sdata.name
		self.names[sname] = self.names[sname].prev
	end
end

function asmmeta:name(n, isparam)
	local prevscope = self.names[n]
	local newscope = { prev = prevscope, isparam = isparam }
	self.scopedata[#self.scopedata+1] = newscope
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
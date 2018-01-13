#!/bin/lua
local lex = require './luart/lex'

local rlex = {}
for k, v in pairs(lex) do
	rlex[v] = k
end

for i=1,select('#', ...) do
	local srcfile = select(i, ...)
	local lexer = io.popen("./scripts/luac-lex.js '" .. srcfile:gsub("'", "'\\''") .. "'")
	local data = lexer:read('a')
	local lx, offs = string.unpack('<s4', data)
	local vlen, offs = string.unpack('<i4', data, offs)
	local vals = {}
	for i=1,vlen do
		local ty = data:byte(offs)
		if ty == 0 then
			vals[i], offs = string.unpack('<i8', data, offs+1)
		elseif ty == 1 then
			vals[i], offs = string.unpack('<d', data, offs+1)
		else
			vals[i], offs = string.unpack('<s4', data, offs+1)
		end
	end
	local i = 1
	while i < #lx do
		local lxi = lx:byte(i)
		local args = {i, rlex[lxi]}
		if lxi&192 ~= 0 then
			args[3], args[4], args[5], args[6], args[7] = string.byte(lx, i, i+5)
			args[8] = vals[string.unpack('<i4', lx, i+1)+1]
			i = i + 5
		else
			args[3] = string.byte(lx, i)
			i = i + 1
		end
		print(table.unpack(args))
	end
end

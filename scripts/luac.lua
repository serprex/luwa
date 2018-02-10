#!/usr/bin/env lua
package.path = 'rt/?.lua;' .. package.path
local astgen = require 'astgen'
local bcgen = require 'bcgen'

local function pprintcore(x, dep, hist)
	local a = string.rep(' ', dep)
	if hist[x] then
		return print(a .. '...', x)
	end
	hist[x] = true
	if type(x.val) == 'function' then
		print(a .. 'val:', x:val())
	end
	for k,v in pairs(x) do
		if k ~= 'mother' and k ~= 'father' then
			if type(v) == 'table' then
				print(a .. tostring(k), v)
				pprintcore(v, dep+1, hist)
			elseif k == 'lex' and type(v) == 'string' then
				print(a .. k, table.concat(table.pack(string.byte(v, 1, #v)), ','))
			else
				print(a .. tostring(k),v)
			end
		end
	end
end
local function pprint(x)
	pprintcore(x, 0, {})
	return x
end

local result = {}
local prevsult = {
	integer = {},
	float = {},
	string = {},
}

local funcnums, funcprefix
local strconst = {}
local function func2lua(func, toplevel)
	local name = funcprefix .. funcnums
	funcnums = funcnums + 1
	local subfuncs = {}
	local consts = {}
	for i=1, #func.consts do
		local c = func.consts[i]
		local ct = math.type(c) or type(c)
		consts[#consts+1] = strconst[ct](c)
	end
	local constlit
	if #consts > 0 then
		constlit = '{' .. table.concat(consts, ',') .. '}'
	else
		constlit = 'nil'
	end
	result[#result+1] = "{'" .. name .. "'," .. #func.params .. "," .. tostring(func.isdotdotdot) .. "," .. string.format('%q', string.char(table.unpack(func.bc))) .. "," .. constlit .. "," .. #func.locals .. "}"
	return name
end
function strconst.integer(c)
	if prevsult.integer[c] then
		return prevsult.integer[c]
	else
		local pack = string.format('%q', string.pack('<i8', c))
		result[#result+1] = "string.unpack('<i8'," .. pack .. ")"
		prevsult.integer[c] = 'function() return GN.integer[' .. pack .. '] end'
		return prevsult.integer[c]
	end
end
function strconst.float(c)
	if prevsult.float[c] then
		return prevsult.float[c]
	else
		local pack = string.format('%q', string.pack('<d', c))
		result[#result+1] = "string.unpack('<d'," .. pack .. ")"
		prevsult.float[c] = 'function() return GN.float[' .. pack .. '] end'
		return prevsult.float[c]
	end
end
function strconst.string(c)
	if prevsult.string[c] then
		return prevsult.string[c]
	else
		local pack = string.format('%q', c)
		result[#result+1] = pack
		prevsult.string[c] = 'function() return GS[' .. pack .. '] end'
		return prevsult.string[c]
	end
end
function strconst.table(c)
	return 'function() return GF.' .. func2lua(c) .. ' end'
end
local lexers = {}
for i=2,select('#', ...) do
	local srcfile = select(i, ...)
	lexers[srcfile] = io.popen("./scripts/luac-lex.js '" .. srcfile:gsub("'", "'\\''") .. "'")
end
for i=2,select('#', ...) do
	local srcfile = select(i, ...)
	local data = lexers[srcfile]:read('a')
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

	funcnums = 0
	funcprefix = srcfile:gsub('^.*/(.*)%.lua$', '%1')
	func2lua(bcgen(astgen(lx, vals)))
end
local f = assert(io.open(..., 'w'))
f:write('return function() return ', table.concat(result, ','),' end')
f:close()

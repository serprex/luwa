-- The prelude's bytecode, compiled by scripts/luac.js. Gives the static objects rt.lua makes:
-- each constant once, then each function after what it uses, as { name, paramc, isdotdotdot, bc, consts, localc }
return function(...)
	local result = {}
	local prevsult = {
		integer = {},
		float = {},
		string = {},
	}
	local funcnums, funcprefix
	local func2lua
	local function konst(kind, c)
		local key = kind == 'integer' and string.pack('<i8', c) or kind == 'float' and string.pack('<d', c) or c
		if not prevsult[kind][key] then
			result[#result+1] = c
			if kind == 'string' then
				prevsult[kind][key] = function() return GS[c] end
			else
				prevsult[kind][key] = function() return GN[kind][key] end
			end
		end
		return prevsult[kind][key]
	end
	function func2lua(fn)
		local name = funcprefix .. funcnums
		funcnums = funcnums + 1
		local consts = {}
		for i, k in ipairs(fn.k) do
			if k[1] == 's' then
				consts[i] = konst('string', k[2])
			elseif k[1] == 'i' then
				consts[i] = konst('integer', (string.unpack('<i8', k[2])))
			elseif k[1] == 'f' then
				consts[i] = konst('float', (string.unpack('<d', k[2])))
			else
				local sub = func2lua(k[2])
				consts[i] = function() return GF[sub] end
			end
		end
		result[#result+1] = { name, fn.p, fn.v, fn.b, #consts > 0 and consts or nil, fn.l }
		return name
	end
	local args = {}
	for i = 1, select('#', ...) do
		args[i] = "'" .. select(i, ...):gsub("'", "'\\''") .. "'"
	end
	require('make').dep('scripts/luac.js', 'scripts/comp.wasm', ...)
	local h = io.popen('node scripts/luac.js ' .. table.concat(args, ' '))
	local fns = load(h:read('a'))()
	assert(h:close(), 'scripts/luac.js failed')
	for i = 1, select('#', ...) do
		funcnums = 0
		funcprefix = select(i, ...):gsub('^.*/(.*)%.lua$', '%1')
		func2lua(fns[i])
	end
	return result
end

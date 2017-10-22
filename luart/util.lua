local function encode_type(x)
	local t = type(x)
	if t == 'number' then
		if math.type(x) == 'integer' then
			return 'j'
		else
			return 'n'
		end
	elseif t == 'string' then
		return 'c'..#x
	elseif t == 'boolean' then
		if t then
			return false, '1'
		else
			return false, '0'
		end
	elseif t == 'nil' then
		return false, 'N'
	end
end

local function encode(x)
	local et, raw = encode_type(x)
	if et then
		return string.char(#et) .. et .. string.pack(et, x)
	else
		return raw
	end
end

local function encodex(...)
	local ret = {}
	for i=1, select('#', ...) do
		ret[i] = encode(select(i, ...))
	end
	return table.concat(ret)
end

local specials = {
	[48] = false,
	[49] = true,
}

local function decode(x, i)
	if not i then
		i = 1
	end
	local a = string.byte(x, i)
	if a < 32 then
		local fmt = string.sub(x, i+1, i+a)
		return string.unpack(fmt, x, i+a+1)
	else
		return specials[a], i+1
	end
end

local function decodex(x)
	local i, ret = 1, {}
	while i <= #x do
		ret[#ret+1], i = decode(x, i)
	end
	return ret
end

return {
	encode = encode,
	decode = decode,
	encodex = encodex,
	decodex = decodex,
}

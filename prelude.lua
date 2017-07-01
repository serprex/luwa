_VERSION = "Luwa 0.0.1"
_G = _ENV

math.mininteger = -9223372036854775808
math.maxinteger = -9223372036854775807
math.pi = 0x1.921fb54442d18p1
math.huge = 1./0.

function string.len(s)
	assert(type(s) == "string", "bad argument #1 to 'len' (string expected)")
	return #s
end

function table.pack(...)
	return { n = select('#', ...), ... }
end

function assert(v, message, ...)
	if v then
		return error(message, 2)
	else
		return v, message, ...
	end
end

function print(...)
	for i in 1 .. select('#', ...) do
		if i > 0 then
			io.write('\t')
		end
		io.write(select(i, ...))
	end
end

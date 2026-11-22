local _luwa = ...
_G = _ENV

math.mininteger = -9223372036854775807 - 1 -- 9223372036854775808 alone is a float
math.maxinteger = 9223372036854775807
math.pi = 0x1.921fb54442d18p1
math.huge = 1./0.
package.config = '/\n;\n?\n!\n-\n'
package.loaded = {
	_G = _ENV,
	coroutine = coroutine,
	debug = debug,
	io = io,
	math = math,
	os = os,
	package = package,
	string = string,
	table = table,
	utf8 = utf8,
}

-- A float with an integer value becomes that integer, anything else but an integer gives nil
function math.tointeger(x)
	local ty = math.type(x)
	if ty == 'integer' then
		return x
	elseif ty == 'float' and x >= -0x1p63 and x < 0x1p63 and x == x // 1 then
		return math.floor(x)
	end
end

-- Remainder of a / b, rounded toward zero, so it has the sign of a, like C fmod
function math.fmod(a, b)
	if math.type(a) == 'integer' and math.type(b) == 'integer' then
		if b == 0 then
			error("bad argument #2 to 'fmod' (zero)", 2)
		elseif b == -1 then
			return 0 -- avoids minint % -1
		end
		local m = a % b
		-- Lua's % has the sign of b, flip it to the sign of a
		if m ~= 0 and (m ~ a) < 0 then
			m = m - b
		end
		return m
	end
	local x, y = tonumber(a), tonumber(b)
	if not x then
		error("bad argument #1 to 'fmod' (number expected, got " .. type(a) .. ")", 2)
	elseif not y then
		error("bad argument #2 to 'fmod' (number expected, got " .. type(b) .. ")", 2)
	end
	x, y = x + 0.0, y + 0.0
	if x ~= x or y ~= y or y == 0 or x == 1 / 0 or x == -1 / 0 then
		return 0.0 / 0.0
	end
	local r, d = x < 0 and -x or x, y < 0 and -y or y
	if r < d then
		return x
	end
	-- Long division in binary. Each subtraction is exact since t <= r < 2t
	local t = d
	while t * 2 <= r do
		t = t * 2
	end
	while t >= d do
		if r >= t then
			r = r - t
		end
		t = t / 2
	end
	if x < 0 then
		return -r
	end
	return r
end

-- capture globals so that behavior doesn't change if rebound
local _rawget, _type = rawget, type
local _error, _next, _select, _pcall = error, next, select, pcall
local debug_getmetatable, debug_setmetatable = debug.getmetatable, debug.setmetatable
local tointeger, math_type = math.tointeger, math.type
local string_byte, string_char = string.byte, string.char
local table_unpack = table.unpack
local co_create, co_resume, co_running = coroutine.create, coroutine.resume, coroutine.running
local math_floor, math_ceil = math.floor, math.ceil


-- String metatable. Arith metamethods get added below, like Lua 5.4
local strmt = { __index = string }
debug_setmetatable('', strmt)

local function _assert(v, ...)
	if v then
		return v, ...
	elseif _select('#', ...) == 0 then
		return _error('assertion failed!', 2)
	else
		return _error(..., 2)
	end
end
assert = _assert

-- table.unpack is native
table_unpack = table.unpack
local string_sub = string.sub
local reinterp = _luwa.reinterp

-- string.pack & string.unpack. Ints of 1 to 8 bytes, doubles, strings.
-- Alignment ('!') is read but ignored, floats ('f') aren't done
local packsizes = {
	[98] = 1, [66] = 1, -- b B
	[104] = 2, [72] = 2, -- h H
	[105] = 4, [73] = 4, -- i I
	[108] = 8, [76] = 8, -- l L
	[106] = 8, [74] = 8, -- j J
	[84] = 8, -- T
}
-- Reads one option of fmt at i. Gives the next i, option byte & size
local function packopt(fmt, i)
	local c = string_byte(fmt, i)
	i = i + 1
	local n = 0
	local d = string_byte(fmt, i)
	while d and d >= 48 and d <= 57 do
		n = n * 10 + d - 48
		i = i + 1
		d = string_byte(fmt, i)
	end
	return i, c, n
end
-- n bytes of x, little endian first
local function intbytes(out, x, n, little)
	local k = #out
	for j = 0, n - 1 do
		local b = j < 8 and (x >> (j * 8) & 255) or (x < 0 and 255 or 0)
		if little then
			out[k + 1 + j] = b
		else
			out[k + n - j] = b
		end
	end
end
function string.pack(fmt, ...)
	-- the common case, from luwa's compiler
	if fmt == '<i4' then
		local x = ...
		return string_char(x & 255, x >> 8 & 255, x >> 16 & 255, x >> 24 & 255)
	end
	local out, argi, little = {}, 1, true
	local i, n = 1, #fmt
	while i <= n do
		local c, sz
		i, c, sz = packopt(fmt, i)
		if c == 60 or c == 61 then -- < =
			little = true
		elseif c == 62 then -- >
			little = false
		elseif c == 33 or c == 32 then -- ! space
		elseif packsizes[c] then
			local x = _select(argi, ...)
			argi = argi + 1
			local v = tointeger(x)
			if not v then
				v = tointeger(tonumber(x))
			end
			_assert(v, "bad argument #" .. argi .. " to 'pack' (number has no integer representation)")
			intbytes(out, v, (c == 105 or c == 73) and sz > 0 and sz or packsizes[c], little)
		elseif c == 100 or c == 110 then -- d n
			local x = _select(argi, ...)
			argi = argi + 1
			intbytes(out, reinterp(x + 0.0), 8, little)
		elseif c == 115 or c == 122 then -- s z
			local s = _select(argi, ...)
			argi = argi + 1
			if _type(s) == 'number' then
				s = s .. ''
			end
			_assert(_type(s) == 'string', "bad argument #" .. argi .. " to 'pack' (string expected)")
			if c == 115 then
				intbytes(out, #s, sz > 0 and sz or 8, little)
			end
			local k = #out
			for j = 1, #s do
				out[k + j] = string_byte(s, j)
			end
			if c == 122 then
				out[#out + 1] = 0
			end
		elseif c == 120 then -- x
			out[#out + 1] = 0
		else
			_error("invalid format option '" .. string_char(c) .. "'")
		end
	end
	return string_char(table_unpack(out))
end
-- Size of what string.pack makes, alignment ignored like pack
function string.packsize(fmt)
	local size, i, n = 0, 1, #fmt
	while i <= n do
		local c, sz
		i, c, sz = packopt(fmt, i)
		if packsizes[c] then
			size = size + ((c == 105 or c == 73) and sz > 0 and sz or packsizes[c])
		elseif c == 100 or c == 110 then -- d n
			size = size + 8
		elseif c == 102 then -- f
			size = size + 4
		elseif c == 99 then -- c
			size = size + sz
		elseif c == 120 then -- x
			size = size + 1
		elseif c == 115 or c == 122 then -- s z
			_error("bad argument #1 to 'packsize' (variable-length format)")
		elseif not (c == 60 or c == 61 or c == 62 or c == 33 or c == 32 or c == 88) then -- < = > ! space X
			_error("invalid format option '" .. string_char(c) .. "'")
		end
	end
	return size
end
function string.unpack(fmt, s, pos)
	pos = pos or 1
	if pos < 0 then
		pos = #s + pos + 1
	end
	-- the common case, from luwa's compiler
	if fmt == '<i4' then
		local a, b, c, d = string_byte(s, pos, pos + 3)
		_assert(d, "data string too short")
		local x = a | b << 8 | c << 16 | d << 24
		if x >= 0x80000000 then
			x = x - 0x100000000
		end
		return x, pos + 4
	end
	local res, little = {}, true
	local i, n = 1, #fmt
	local function getint(sz, signed)
		_assert(pos + sz - 1 <= #s, "data string too short")
		local x = 0
		for j = 0, sz - 1 do
			local b = string_byte(s, little and pos + j or pos + sz - 1 - j)
			if j < 8 then
				x = x | b << (j * 8)
			end
		end
		pos = pos + sz
		if signed and sz < 8 and x >= 1 << (sz * 8 - 1) then
			x = x - (1 << (sz * 8))
		end
		return x
	end
	while i <= n do
		local c, sz
		i, c, sz = packopt(fmt, i)
		if c == 60 or c == 61 then
			little = true
		elseif c == 62 then
			little = false
		elseif c == 33 or c == 32 then
		elseif packsizes[c] then
			res[#res + 1] = getint((c == 105 or c == 73) and sz > 0 and sz or packsizes[c], c >= 97)
		elseif c == 100 or c == 110 then
			res[#res + 1] = reinterp(getint(8, true))
		elseif c == 115 then
			local len = getint(sz > 0 and sz or 8, false)
			_assert(pos + len - 1 <= #s, "data string too short")
			res[#res + 1] = string_sub(s, pos, pos + len - 1)
			pos = pos + len
		elseif c == 122 then
			local e = pos
			while string_byte(s, e) ~= 0 do
				_assert(e <= #s, "unfinished string for format 'z'")
				e = e + 1
			end
			res[#res + 1] = string_sub(s, pos, e - 1)
			pos = e + 1
		elseif c == 120 then
			pos = pos + 1
		else
			_error("invalid format option '" .. string_char(c) .. "'")
		end
	end
	res[#res + 1] = pos
	return table_unpack(res)
end

local function _getmetatable(object)
	object = debug_getmetatable(object)
	return (_type(object) == 'table' and _rawget(object, '__metatable')) or object
end
getmetatable = _getmetatable

function setmetatable(table, metatable)
	_assert(_type(table) == 'table')
	_assert(metatable == nil or _type(metatable) == 'table')
	local mt = debug_getmetatable(table)
	if mt then
		_assert(not _rawget(mt, '__metatable'), 'cannot change a protected metatable')
	end
	return debug_setmetatable(table, metatable)
end

-- Object id as 8 hex digits, what tostring shows in place of an address
local hexdigits = '0123456789abcdef'
local function hexid(v)
	local id = _luwa.objid(v) & 0xffffffff
	local out = {}
	for i = 8, 1, -1 do
		out[i] = string_byte(hexdigits, (id & 15) + 1)
		id = id >> 4
	end
	return '0x' .. string_char(table_unpack(out, 1, 8))
end

local function _tostring(v)
	local ty = _type(v)
	if ty == 'string' then
		return v
	elseif ty == 'number' then
		return v .. ''
	elseif v == nil then
		return 'nil'
	elseif v == true then
		return 'true'
	elseif v == false then
		return 'false'
	else
		local mt = debug_getmetatable(v)
		local __tostring = mt and _rawget(mt, '__tostring')
		if __tostring then
			local s = __tostring(v)
			local sty = _type(s)
			if sty == 'string' then
				return s
			elseif sty == 'number' then
				return s .. ''
			else
				_error("'__tostring' must return a string")
			end
		else
			return ty .. ': ' .. hexid(v)
		end
	end
end
tostring = _tostring

local digits = {}
for i=0,9 do
	digits[48+i] = i
end
for i=10,35 do
	digits[55+i] = i
	digits[87+i] = i
end
local string_unpack = string.unpack
-- whitespace that tonumber skips around a number
local spaces = { [9] = true, [10] = true, [11] = true, [12] = true, [13] = true, [32] = true }
-- First & last non space position of s, and whether there's a sign there.
-- Returns i, j, neg, where s[i..j] is what's left after the sign
local function numbounds(s)
	local i, j = 1, #s
	while i <= j and spaces[string_byte(s, i)] do
		i = i + 1
	end
	while i <= j and spaces[string_byte(s, j)] do
		j = j - 1
	end
	local ch = i <= j and string_byte(s, i)
	local neg = ch == 45 -- '-'
	if neg or ch == 43 then -- '+'
		i = i + 1
	end
	return i, j, neg
end
-- Count of digits (in base 10, or 16 if hex) starting at s[i], up to j
local function digitrun(s, i, j, hex)
	local n = 0
	while i + n <= j do
		local d = digits[string_byte(s, i + n)] -- i + n <= j, so never nil
		if not d or d >= (hex and 16 or 10) then
			break
		end
		n = n + 1
	end
	return n
end
-- Whether s[i..j] is a Lua numeral, & whether it's a plain decimal integer
local function isnumeral(s, i, j)
	local hex = false
	local a, b = string_byte(s, i, i + 1)
	if i + 1 <= j and a == 48 and (b == 120 or b == 88) then -- 0x
		hex = true
		i = i + 2
	end
	local n = digitrun(s, i, j, hex)
	i = i + n
	local plain = not hex
	if i <= j and string_byte(s, i) == 46 then -- '.'
		plain = false
		local m = digitrun(s, i + 1, j, hex)
		i = i + 1 + m
		n = n + m
	end
	if n == 0 then
		return false
	end
	local e = string_byte(s, i)
	if i <= j and (hex and (e == 112 or e == 80) or not hex and (e == 101 or e == 69)) then
		plain = false
		i = i + 1
		e = string_byte(s, i)
		if e == 43 or e == 45 then
			i = i + 1
		end
		local m = digitrun(s, i, j, false)
		if m == 0 then
			return false
		end
		i = i + m
	end
	return i == j + 1, plain
end
function tonumber(num, base)
	if base == nil then
		if _type(num) == 'number' then
			return num
		elseif _type(num) ~= 'string' then
			return nil
		end
		local i, j, neg = numbounds(num)
		local ok, plain = isnumeral(num, i, j)
		if not ok then
			return nil
		end
		-- the lexer gives the exact value. A valid numeral lexes as 1 number token
		-- no string.sub yet, so copy out the numeral byte by byte
		local lx, vals = _luwa.lexgen(string_char(string_byte(num, i, j)))
		local v = vals[string_unpack('<i4', lx, 2) + 1]
		if neg then
			-- -9223372036854775808 fits in an integer, but the lexer only saw 9223372036854775808
			if plain and v == 0x1p63 then
				return -0x7fffffffffffffff - 1
			end
			v = -v
		end
		return v
	else
		base = _assert(tointeger(base), "bad argument #2 to 'tonumber' (number expected, got string)")
		_assert(_type(num) == 'string', "bad argument #1 to 'tonumber' (string expected, got number)")
		_assert(base > 1 and base < 37, "bad argument #2 to 'tonumber' (base out of range)")
		local i, j, neg = numbounds(num)
		if i > j then
			return nil
		end
		-- integers wrap on overflow, like Lua
		local ret = 0
		for k = i, j do
			local ch = digits[string_byte(num, k)]
			if not ch or ch >= base then
				return nil
			end
			ret = ret * base + ch
		end
		return neg and -ret or ret
	end
end

math.atan2 = math.atan
function math.deg(x)
	return x * (180./0x1.921fb54442d18p1)
end
function math.max(x, ...)
	for i = 1,_select('#', ...) do
		local m = _select(i, ...)
		if m > x then
			x = m
		end
	end
	return x
end
function math.min(x, ...)
	for i = 1,_select('#', ...) do
		local m = _select(i, ...)
		if m < x then
			x = m
		end
	end
	return x
end
function math.modf(x)
	if x > 0 then
		local xi = math_floor(x)
		return xi, x - xi
	else
		local xi = math_ceil(x)
		return -xi, x + xi
	end
end
function math.pow(x, y)
	return x ^ y
end
function math.rad(x)
	return x * (0x1.921fb54442d18p1/180.)
end
local randomseed = 1 + math_floor(_luwa.random() * 0x7ffffffffffffff7)
function math.random()
	-- xorshift* from wikipedia
	randomseed = randomseed ~ (randomseed>>12)
	randomseed = randomseed ~ (randomseed<<25)
	randomseed = randomseed ~ (randomseed>>27)
	return randomseed * 0x2545f4914f6cdd1d
end
function math.randomseed(x)
	randomseed = math_floor(x)
end
function math.sqrt(x)
	return x ^ .5
end
function math.ult(m, n)
	m = tointeger(m)
	_assert(m, "bad argument #1 to 'ult'")
	n = tointeger(n)
	_assert(n, "bad argument #2 to 'ult'")
	if m >= 0 then
		return n < 0 or m < n
	else
		return n < 0 and m < n
	end
end

function string:len()
	_assert(_type(self) == "string", "bad argument #1 to 'len' (string expected)")
	return #self
end
-- Fallback when a string won't convert: try y's metamethod
local function smtfb(meth, x, y)
	local yt = _type(y)
	if yt ~= 'string' then
		local mt = debug_getmetatable(y)
		if mt then
			local fn = _rawget(mt, meth)
			if fn then
				return fn(x, y)
			end
		end
	end
	return error("attempt to " .. meth .. " a '" .. _type(x) .. "' with a '" .. yt .. "'")
end
function strmt.__add(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx + ny
	else
		return smtfb('__add', x, y)
	end
end
function strmt.__sub(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx - ny
	else
		return smtfb('__sub', x, y)
	end
end
function strmt.__mul(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx * ny
	else
		return smtfb('__mul', x, y)
	end
end
function strmt.__mod(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx % ny
	else
		return smtfb('__mod', x, y)
	end
end
function strmt.__pow(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx ^ ny
	else
		return smtfb('__pow', x, y)
	end
end
function strmt.__div(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx / ny
	else
		return smtfb('__div', x, y)
	end
end
function strmt.__idiv(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx // ny
	else
		return smtfb('__idiv', x, y)
	end
end
function strmt:__unm()
	local nx = tonumber(self)
	if nx ~= nil then
		return -nx
	else
		return error("attempt to unm a 'string'")
	end
end

-- Position i of a string of length len, negative counts from the end
local function posrelat(i, len)
	if i >= 0 then
		return i
	elseif -i > len then
		return 0
	else
		return len + i + 1
	end
end

-- the wasm string.char wraps values outside 0-255, so check them here
function string.char(...)
	local t = { ... }
	for i = 1, _select('#', ...) do
		local c = tointeger(t[i])
		if not c or c < 0 or c > 255 then
			_error("bad argument #" .. i .. " to 'char' (" .. (c and "value out of range" or "number has no integer representation") .. ")")
		end
	end
	return string_char(...)
end
function string.rep(s, n, sep)
	if n <= 0 then
		return ''
	elseif sep and sep ~= '' then
		return string.rep(s .. sep, n - 1) .. s
	end
	-- doubling: s, ss, ssss, ...
	local r = ''
	while true do
		if n & 1 == 1 then
			r = r .. s
		end
		n = n >> 1
		if n == 0 then
			return r
		end
		s = s .. s
	end
end

-- Apply fn to each byte of s, 4096 at a time so string.char doesn't get too many args
local function mapbytes(s, fn)
	local parts = {}
	for i = 1, #s, 4096 do
		local t = { string_byte(s, i, i + 4095) }
		for j = 1, #t do
			t[j] = fn(t[j])
		end
		parts[#parts + 1] = string_char(table_unpack(t))
	end
	return table.concat(parts)
end
function string.upper(s)
	return mapbytes(s, function(c)
		return (c >= 97 and c <= 122) and c - 32 or c
	end)
end
function string.lower(s)
	return mapbytes(s, function(c)
		return (c >= 65 and c <= 90) and c + 32 or c
	end)
end
function string.reverse(s)
	local t = {}
	for i = #s, 1, -1 do
		t[#t + 1] = string_byte(s, i)
	end
	local parts = {}
	for i = 1, #t, 4096 do
		parts[#parts + 1] = string_char(table_unpack(t, i, i + 4095 < #t and i + 4095 or #t))
	end
	return table.concat(parts)
end

-- Lua patterns, a port of lstrlib.c's matcher. One match runs at a time:
-- the state is these upvalues, set by setstate before each match
local msrc, mslen, mpat, mplen, mlevel
local capinit, caplen = {}, {}
local CAP_UNF, CAP_POS = -1, -2
local function setstate(s, p)
	msrc, mslen, mpat, mplen, mlevel = s, #s, p, #p, 0
end

-- character classes, by class letter: a set of bytes
local classes = {}
do
	local function set(letter, test)
		local t = {}
		for c = 0, 255 do
			t[c] = test(c) or nil
		end
		classes[letter] = t
	end
	local function isalpha(c) return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) end
	local function isdigit(c) return c >= 48 and c <= 57 end
	local function ispunct(c) return (c >= 33 and c <= 47) or (c >= 58 and c <= 64) or (c >= 91 and c <= 96) or (c >= 123 and c <= 126) end
	set(97, isalpha) -- a
	set(99, function(c) return c < 32 or c == 127 end) -- c
	set(100, isdigit) -- d
	set(103, function(c) return c > 32 and c < 127 end) -- g
	set(108, function(c) return c >= 97 and c <= 122 end) -- l
	set(112, ispunct) -- p
	set(115, function(c) return c == 32 or (c >= 9 and c <= 13) end) -- s
	set(117, function(c) return c >= 65 and c <= 90 end) -- u
	set(119, function(c) return isalpha(c) or isdigit(c) end) -- w
	set(120, function(c) return isdigit(c) or (c >= 65 and c <= 70) or (c >= 97 and c <= 102) end) -- x
end
local function matchclass(c, cl)
	local upper = cl >= 65 and cl <= 90
	local set = classes[upper and cl + 32 or cl]
	if not set then
		return cl == c
	elseif upper then
		return not set[c]
	else
		return set[c] == true
	end
end

-- index just past the single char class at p
local function classend(p)
	local c = string_byte(mpat, p)
	p = p + 1
	if c == 37 then -- %
		if p > mplen then
			_error("malformed pattern (ends with '%')")
		end
		return p + 1
	elseif c == 91 then -- [
		if string_byte(mpat, p) == 94 then
			p = p + 1
		end
		repeat
			if p > mplen then
				_error("malformed pattern (missing ']')")
			end
			local cc = string_byte(mpat, p)
			p = p + 1
			if cc == 37 and p <= mplen then
				p = p + 1
			end
		until string_byte(mpat, p) == 93
		return p + 1
	else
		return p
	end
end
-- does c match the set [...] from p (at '[') to ec (at ']')
local function matchbracket(c, p, ec)
	local sig = true
	p = p + 1
	if string_byte(mpat, p) == 94 then
		sig = false
		p = p + 1
	end
	while p < ec do
		local pc = string_byte(mpat, p)
		if pc == 37 then
			p = p + 1
			if matchclass(c, string_byte(mpat, p)) then
				return sig
			end
		elseif string_byte(mpat, p + 1) == 45 and p + 2 < ec then -- a-z
			if pc <= c and c <= string_byte(mpat, p + 2) then
				return sig
			end
			p = p + 2
		elseif pc == c then
			return sig
		end
		p = p + 1
	end
	return not sig
end
local function singlematch(s, p, ep)
	if s > mslen then
		return false
	end
	local c = string_byte(msrc, s)
	local pc = string_byte(mpat, p)
	if pc == 46 then -- .
		return true
	elseif pc == 37 then
		return matchclass(c, string_byte(mpat, p + 1))
	elseif pc == 91 then
		return matchbracket(c, p, ep - 1)
	else
		return pc == c
	end
end

local domatch
local function maxexpand(s, p, ep)
	local i = 0
	while singlematch(s + i, p, ep) do
		i = i + 1
	end
	while i >= 0 do
		local res = domatch(s + i, ep + 1)
		if res then
			return res
		end
		i = i - 1
	end
end
local function minexpand(s, p, ep)
	while true do
		local res = domatch(s, ep + 1)
		if res then
			return res
		elseif singlematch(s, p, ep) then
			s = s + 1
		else
			return nil
		end
	end
end
local function startcapture(s, p, what)
	mlevel = mlevel + 1
	capinit[mlevel] = s
	caplen[mlevel] = what
	local res = domatch(s, p)
	if not res then
		mlevel = mlevel - 1
	end
	return res
end
local function endcapture(s, p)
	local l
	for k = mlevel, 1, -1 do
		if caplen[k] == CAP_UNF then
			l = k
			break
		end
	end
	if not l then
		_error('invalid pattern capture')
	end
	caplen[l] = s - capinit[l]
	local res = domatch(s, p)
	if not res then
		caplen[l] = CAP_UNF
	end
	return res
end
local function matchbalance(s, p)
	if p + 1 > mplen then
		_error("malformed pattern (missing arguments to '%b')")
	end
	local b, e = string_byte(mpat, p, p + 1)
	if s > mslen or string_byte(msrc, s) ~= b then
		return nil
	end
	local cont = 1
	s = s + 1
	while s <= mslen do
		local c = string_byte(msrc, s)
		if c == e then
			cont = cont - 1
			if cont == 0 then
				return s + 1
			end
		elseif c == b then
			cont = cont + 1
		end
		s = s + 1
	end
end
local function matchcapture(s, l)
	l = l - 48
	if l < 1 or l > mlevel or caplen[l] == CAP_UNF then
		_error('invalid capture index %' .. l)
	end
	local len = caplen[l]
	if mslen - s + 1 >= len and
		string_sub(msrc, capinit[l], capinit[l] + len - 1) == string_sub(msrc, s, s + len - 1) then
		return s + len
	end
end
-- Match from s with pattern at p. Gives the index past the match, or nil
function domatch(s, p)
	while true do
		if p > mplen then
			return s
		end
		local pc = string_byte(mpat, p)
		local nc = string_byte(mpat, p + 1)
		if pc == 40 then -- (
			if nc == 41 then
				return startcapture(s, p + 2, CAP_POS)
			else
				return startcapture(s, p + 1, CAP_UNF)
			end
		elseif pc == 41 then -- )
			return endcapture(s, p + 1)
		elseif pc == 36 and p == mplen then -- $ at the end
			return s == mslen + 1 and s or nil
		elseif pc == 37 and nc == 98 then -- %b
			s = matchbalance(s, p + 2)
			if not s then
				return nil
			end
			p = p + 4
		elseif pc == 37 and nc == 102 then -- %f
			p = p + 2
			if string_byte(mpat, p) ~= 91 then
				_error("missing '[' after '%f' in pattern")
			end
			local ep = classend(p)
			local prev = s == 1 and 0 or string_byte(msrc, s - 1)
			local cur = s <= mslen and string_byte(msrc, s) or 0
			if not matchbracket(prev, p, ep - 1) and matchbracket(cur, p, ep - 1) then
				p = ep
			else
				return nil
			end
		elseif pc == 37 and nc and nc >= 48 and nc <= 57 then -- %0-9
			s = matchcapture(s, nc)
			if not s then
				return nil
			end
			p = p + 2
		else
			local ep = classend(p)
			local epc = string_byte(mpat, ep)
			if not singlematch(s, p, ep) then
				if epc == 42 or epc == 63 or epc == 45 then -- * ? -
					p = ep + 1
				else
					return nil
				end
			elseif epc == 63 then -- ?
				local res = domatch(s + 1, ep + 1)
				if res then
					return res
				end
				p = ep + 1
			elseif epc == 43 then -- +
				return maxexpand(s + 1, p, ep)
			elseif epc == 42 then -- *
				return maxexpand(s, p, ep)
			elseif epc == 45 then -- -
				return minexpand(s, p, ep)
			else
				s = s + 1
				p = ep
			end
		end
	end
end

-- capture i of the match s..e-1
local function getcapture(i, s, e)
	if i > mlevel then
		if i == 1 then
			return string_sub(msrc, s, e - 1)
		end
		_error('invalid capture index %' .. i)
	end
	local l = caplen[i]
	if l == CAP_UNF then
		_error('unfinished capture')
	elseif l == CAP_POS then
		return capinit[i]
	end
	return string_sub(msrc, capinit[i], capinit[i] + l - 1)
end
-- all the captures, or the whole match when there are none
local function getcaptures(s, e, whole)
	local n = (mlevel == 0 and whole) and 1 or mlevel
	local t = {}
	for i = 1, n do
		t[i] = getcapture(i, s, e)
	end
	return table_unpack(t, 1, n)
end

-- any of ^$*+?.([%- in p
local function hasspecials(p)
	for i = 1, #p do
		local c = string_byte(p, i)
		if c == 94 or c == 36 or c == 42 or c == 43 or c == 63 or c == 46 or
			c == 40 or c == 91 or c == 37 or c == 45 then
			return true
		end
	end
	return false
end
local function strfind(s, p, init, plain, find)
	_assert(_type(s) == 'string' or _type(s) == 'number', "bad argument #1 (string expected)")
	_assert(_type(p) == 'string' or _type(p) == 'number', "bad argument #2 (string expected)")
	s = s .. ''
	p = p .. ''
	local slen = #s
	init = posrelat(init or 1, slen)
	if init < 1 then
		init = 1
	elseif init > slen + 1 then
		return nil
	end
	if find and (plain or not hasspecials(p)) then
		local plen = #p
		for i = init, slen - plen + 1 do
			if string_sub(s, i, i + plen - 1) == p then
				return i, i + plen - 1
			end
		end
		return nil
	end
	setstate(s, p)
	local pstart = 1
	local anchor = string_byte(p, 1) == 94
	if anchor then
		pstart = 2
	end
	local s1 = init
	repeat
		mlevel = 0
		local e = domatch(s1, pstart)
		if e then
			if find then
				return s1, e - 1, getcaptures(s1, e, false)
			else
				return getcaptures(s1, e, true)
			end
		end
		s1 = s1 + 1
	until anchor or s1 > slen + 1
	return nil
end
function string.find(s, p, init, plain)
	return strfind(s, p, init, plain, true)
end
function string.match(s, p, init)
	return strfind(s, p, init, false, false)
end
function string.gmatch(s, p, init)
	s = s .. ''
	p = p .. ''
	local pos = posrelat(init or 1, #s)
	if pos < 1 then
		pos = 1
	end
	local lastmatch
	return function()
		setstate(s, p)
		for s1 = pos, #s + 1 do
			mlevel = 0
			local e = domatch(s1, 1)
			if e and e ~= lastmatch then
				pos = e
				lastmatch = e
				return getcaptures(s1, e, true)
			end
		end
	end
end
function string.gsub(s, p, repl, maxn)
	s = s .. ''
	p = p .. ''
	local rty = _type(repl)
	if rty == 'number' then
		repl = repl .. ''
		rty = 'string'
	end
	_assert(rty == 'string' or rty == 'table' or rty == 'function',
		"bad argument #3 to 'gsub' (string/function/table expected, got " .. rty .. ")")
	maxn = maxn or #s + 1
	local slen = #s
	local pstart = 1
	local anchor = string_byte(p, 1) == 94
	if anchor then
		pstart = 2
	end
	local out = {}
	local s1, copyfrom, n, lastmatch = 1, 1, 0, nil
	setstate(s, p)
	while n < maxn do
		mlevel = 0
		local e = domatch(s1, pstart)
		if e and e ~= lastmatch then
			n = n + 1
			out[#out + 1] = string_sub(s, copyfrom, s1 - 1)
			local whole = string_sub(s, s1, e - 1)
			local v
			if rty == 'string' then
				-- %0-9 & %% in repl
				local parts, i, rl = {}, 1, #repl
				while i <= rl do
					local c = string_byte(repl, i)
					if c == 37 then
						i = i + 1
						local d = string_byte(repl, i)
						if d == 37 then
							parts[#parts + 1] = '%'
						elseif d and d >= 48 and d <= 57 then
							if d == 48 then
								parts[#parts + 1] = whole
							else
								local cap = getcapture(d - 48, s1, e)
								parts[#parts + 1] = _type(cap) == 'number' and cap .. '' or cap
							end
						else
							_error("invalid use of '%' in replacement string")
						end
					else
						-- copy up to the next %
						local j = i
						while j < rl and string_byte(repl, j + 1) ~= 37 do
							j = j + 1
						end
						parts[#parts + 1] = string_sub(repl, i, j)
						i = j
					end
					i = i + 1
				end
				v = table.concat(parts)
			elseif rty == 'table' then
				v = repl[getcapture(1, s1, e)]
			else
				v = repl(getcaptures(s1, e, true))
			end
			-- repl may have run other matches
			setstate(s, p)
			if not v then
				v = whole
			elseif _type(v) == 'number' then
				v = v .. ''
			elseif _type(v) ~= 'string' then
				_error('invalid replacement value (a ' .. _type(v) .. ')')
			end
			out[#out + 1] = v
			s1 = e
			copyfrom = e
			lastmatch = e
		elseif s1 <= slen then
			s1 = s1 + 1
		else
			break
		end
		if anchor then
			break
		end
	end
	out[#out + 1] = string_sub(s, copyfrom)
	return table.concat(out), n
end

-- %q of a string: escapes ", \, newline & control chars, like lstrlib.c
local function quotestr(s)
	local out = { '"' }
	local i, n = 1, #s
	while i <= n do
		-- copy plain bytes in runs
		local j = i
		while j <= n do
			local c = string_byte(s, j)
			if c == 34 or c == 92 or c < 32 or c == 127 then
				break
			end
			j = j + 1
		end
		if j > i then
			out[#out + 1] = string_sub(s, i, j - 1)
		end
		if j > n then
			break
		end
		local c = string_byte(s, j)
		if c == 34 or c == 92 or c == 10 then
			out[#out + 1] = '\\' .. string_char(c)
		else
			local nx = string_byte(s, j + 1)
			if nx and nx >= 48 and nx <= 57 then
				local d = c .. ''
				out[#out + 1] = '\\' .. string.rep('0', 3 - #d) .. d
			else
				out[#out + 1] = '\\' .. c
			end
		end
		i = j + 1
	end
	out[#out + 1] = '"'
	return table.concat(out)
end

local host = _luwa.host
function string.format(fmt, ...)
	fmt = fmt .. ''
	local out = {}
	local argi = 0
	local i, n = 1, #fmt
	while i <= n do
		local j = i
		while j <= n and string_byte(fmt, j) ~= 37 do
			j = j + 1
		end
		if j > i then
			out[#out + 1] = string_sub(fmt, i, j - 1)
		end
		if j > n then
			break
		end
		-- a spec: %[flags][width][.precision]conv
		local k = j + 1
		if string_byte(fmt, k) == 37 then
			out[#out + 1] = '%'
			i = k + 1
		else
			while k <= n do
				local c = string_byte(fmt, k)
				if c == 45 or c == 43 or c == 32 or c == 35 or c == 48 then
					k = k + 1
				else
					break
				end
			end
			while k <= n and string_byte(fmt, k) >= 48 and string_byte(fmt, k) <= 57 do
				k = k + 1
			end
			local hasprec = string_byte(fmt, k) == 46
			if hasprec then
				k = k + 1
				while k <= n and string_byte(fmt, k) >= 48 and string_byte(fmt, k) <= 57 do
					k = k + 1
				end
			end
			local conv = string_byte(fmt, k)
			_assert(conv, "invalid conversion '" .. string_sub(fmt, j) .. "' to 'format'")
			local spec = string_sub(fmt, j, k)
			argi = argi + 1
			_assert(argi <= _select('#', ...), "bad argument #" .. (argi + 1) .. " to 'format' (no value)")
			local arg = _select(argi, ...)
			if conv == 100 or conv == 105 or conv == 120 or conv == 88 or conv == 111 or conv == 99 or conv == 117 then
				local v = tointeger(arg)
				if v == nil and _type(arg) == 'string' then
					v = tointeger(tonumber(arg))
				end
				if v == nil then
					_error("bad argument #" .. (argi + 1) .. " to 'format' (" ..
						(_type(arg) == 'number' and 'number has no integer representation' or 'number expected, got ' .. _type(arg)) .. ")")
				end
				out[#out + 1] = host('fmt', spec, v)
			elseif conv == 97 or conv == 65 or conv == 101 or conv == 69 or conv == 102 or conv == 70 or conv == 103 or conv == 71 then
				local v = tonumber(arg)
				_assert(v, "bad argument #" .. (argi + 1) .. " to 'format' (number expected, got " .. _type(arg) .. ")")
				out[#out + 1] = host('fmt', spec, v + 0.0)
			elseif conv == 115 then -- s
				local v = _tostring(arg)
				if #spec == 2 then
					out[#out + 1] = v
				else
					-- precision cuts, width pads
					local flags = string.match(spec, '^%%([-+ #0]*)')
					local w = tonumber(string.match(spec, '^%%[-+ #0]*(%d*)')) or 0
					local p = tonumber(string.match(spec, '%.(%d*)'))
					if hasprec then
						v = string_sub(v, 1, p or 0)
					end
					if #v < w then
						if string.find(flags, '-', 1, true) then
							v = v .. string.rep(' ', w - #v)
						else
							v = string.rep(' ', w - #v) .. v
						end
					end
					out[#out + 1] = v
				end
			elseif conv == 113 then -- q
				local ty = math_type(arg)
				if _type(arg) == 'string' then
					out[#out + 1] = quotestr(arg)
				elseif ty == 'integer' then
					out[#out + 1] = arg == math.mininteger and '0x8000000000000000' or arg .. ''
				elseif ty == 'float' then
					if arg ~= arg then
						out[#out + 1] = '(0/0)'
					elseif arg == 1/0 then
						out[#out + 1] = '1e9999'
					elseif arg == -1/0 then
						out[#out + 1] = '-1e9999'
					elseif arg == math_floor(arg) and arg >= -0x1p63 and arg < 0x1p63 then
						out[#out + 1] = host('fmt', '%a', arg)
					else
						out[#out + 1] = host('fmt', '%a', arg)
					end
				elseif arg == nil or arg == true or arg == false then
					out[#out + 1] = _tostring(arg)
				else
					_error("bad argument #" .. (argi + 1) .. " to 'format' (value has no literal form)")
				end
			elseif conv == 112 then -- p
				local ty = _type(arg)
				if ty == 'table' or ty == 'function' or ty == 'thread' then
					out[#out + 1] = hexid(arg)
				else
					out[#out + 1] = '(null)'
				end
			else
				_error("invalid conversion '" .. spec .. "' to 'format'")
			end
			i = k + 1
		end
	end
	return table.concat(out)
end

-- utf8, like lutf8lib.c. Strict unless lax: no surrogates or values past 10FFFF.
-- Lax allows up to 7FFFFFFF in up to 6 bytes
local utf8limits = { 0x80, 0x800, 0x10000, 0x200000, 0x4000000 }
local function iscont(c)
	return c and c & 0xc0 == 0x80
end
-- Gives codepoint & index after it, or nil
local function utf8dec(s, i, strict)
	local c = string_byte(s, i)
	local res
	if c < 0x80 then
		res = c
	else
		local count = 0
		res = 0
		while c & 0x40 ~= 0 do
			count = count + 1
			local cc = string_byte(s, i + count)
			if not iscont(cc) then
				return nil
			end
			res = res << 6 | (cc & 0x3f)
			c = c << 1
		end
		if count == 0 or count > 5 then -- a lone continuation byte, or too long
			return nil
		end
		res = res | ((c & 0x7f) << (count * 5))
		if res > 0x7fffffff or res < utf8limits[count] then
			return nil
		end
		i = i + count
	end
	if strict and (res > 0x10ffff or (res >= 0xd800 and res <= 0xdfff)) then
		return nil
	end
	return res, i + 1
end
local function utf8int(x, n, fname)
	local v = tointeger(x)
	if v == nil then
		_error("bad argument #" .. n .. " to '" .. fname .. "' (number expected, got " .. _type(x) .. ")")
	end
	return v
end
function utf8.len(s, i, j, lax)
	local len = #s
	i = posrelat(utf8int(i or 1, 2, 'len'), len)
	j = posrelat(utf8int(j or -1, 3, 'len'), len)
	if i < 1 or i - 1 > len then
		_error("bad argument #2 to 'len' (initial position out of bounds)")
	end
	if j > len then
		_error("bad argument #3 to 'len' (final position out of bounds)")
	end
	local n = 0
	while i <= j do
		local cp, ni = utf8dec(s, i, not lax)
		if not cp then
			return nil, i
		end
		i = ni
		n = n + 1
	end
	return n
end
local function utf8enc(x)
	if x < 0x80 then
		return string_char(x)
	end
	-- bytes come out last first, so flip them after
	local b, mfb = {}, 0x3f
	repeat
		b[#b + 1] = 0x80 | (x & 0x3f)
		x = x >> 6
		mfb = mfb >> 1
	until x <= mfb
	b[#b + 1] = (~mfb << 1 | x) & 0xff
	local n = #b
	for k = 1, n // 2 do
		b[k], b[n + 1 - k] = b[n + 1 - k], b[k]
	end
	return string_char(table_unpack(b))
end
function utf8.char(...)
	local out = {}
	for k = 1, _select('#', ...) do
		local c = utf8int(_select(k, ...), k, 'char')
		if c < 0 or c > 0x7fffffff then
			_error("bad argument #" .. k .. " to 'char' (value out of range)")
		end
		out[k] = utf8enc(c)
	end
	return table.concat(out)
end
function utf8.codepoint(s, i, j, lax)
	local len = #s
	i = posrelat(utf8int(i or 1, 2, 'codepoint'), len)
	j = posrelat(utf8int(j or i, 3, 'codepoint'), len)
	if i < 1 then
		_error("bad argument #2 to 'codepoint' (out of bounds)")
	end
	if j > len then
		_error("bad argument #3 to 'codepoint' (out of bounds)")
	end
	local out = {}
	while i <= j do
		local cp, ni = utf8dec(s, i, not lax)
		if not cp then
			_error('invalid UTF-8 code')
		end
		out[#out + 1] = cp
		i = ni
	end
	return table_unpack(out)
end
function utf8.offset(s, n, i)
	local len = #s
	n = utf8int(n, 2, 'offset')
	i = posrelat(utf8int(i or (n >= 0 and 1 or len + 1), 3, 'offset'), len)
	-- i is 0 based from here, like lutf8lib.c
	if i < 1 or i - 1 > len then
		_error("bad argument #3 to 'offset' (position out of bounds)")
	end
	i = i - 1
	if n == 0 then
		while i > 0 and iscont(string_byte(s, i + 1)) do
			i = i - 1
		end
	else
		if iscont(string_byte(s, i + 1)) then
			_error('initial position is a continuation byte')
		end
		if n < 0 then
			while n < 0 and i > 0 do
				repeat
					i = i - 1
				until i <= 0 or not iscont(string_byte(s, i + 1))
				n = n + 1
			end
		else
			n = n - 1
			while n > 0 and i < len do
				repeat
					i = i + 1
				until not iscont(string_byte(s, i + 1))
				n = n - 1
			end
		end
	end
	if n ~= 0 then
		return nil
	end
	local start = i + 1
	local c = string_byte(s, i + 1)
	if c and c & 0x80 ~= 0 then
		if iscont(c) then
			_error('initial position is a continuation byte')
		end
		while iscont(string_byte(s, i + 2)) do
			i = i + 1
		end
	end
	return start, i + 1
end
local function utf8iter(strict)
	return function(s, n)
		local len = #s
		n = tointeger(n) or 0
		-- n is the 1 based start of the last char, so n is the 0 based index after its first byte
		if n < 0 then
			return nil
		end
		if n < len then
			while iscont(string_byte(s, n + 1)) do
				n = n + 1
			end
		end
		if n >= len then
			return nil
		end
		local cp, ni = utf8dec(s, n + 1, strict)
		if not cp or iscont(string_byte(s, ni)) then
			_error('invalid UTF-8 code')
		end
		return n + 1, cp
	end
end
local utf8strict, utf8lax = utf8iter(true), utf8iter(false)
function utf8.codes(s, lax)
	if iscont(string_byte(s, 1)) then
		_error("bad argument #1 to 'codes' (invalid UTF-8 code)")
	end
	return lax and utf8lax or utf8strict, s, 0
end

-- concat halves, so long lists don't copy the same bytes over & over
local function concatrange(t, sep, i, j)
	if i == j then
		local v = t[i]
		local ty = _type(v)
		if ty == 'number' then
			return v .. ''
		elseif ty ~= 'string' then
			_error("invalid value (at index " .. i .. ") in table for 'concat'")
		end
		return v
	end
	local m = (i + j) // 2
	return concatrange(t, sep, i, m) .. sep .. concatrange(t, sep, m + 1, j)
end
function table.concat(t, sep, i, j)
	i = i or 1
	j = j or #t
	if i > j then
		return ''
	end
	return concatrange(t, sep or '', i, j)
end

utf8.charpattern = "[\0-\x7F\xC2-\xFD][\x80-\xBF]*"

function table.pack(...)
	return { n = _select('#', ...), ... }
end
-- The engine sizes tables itself, so this only checks the args
function table.create(narr, nrec)
	nrec = nrec or 0
	_assert(math_type(narr) == 'integer', "bad argument #1 to 'create' (number has no integer representation)")
	_assert(math_type(nrec) == 'integer', "bad argument #2 to 'create' (number has no integer representation)")
	_assert(narr >= 0 and narr <= 0x7fffffff, "bad argument #1 to 'create' (out of range)")
	_assert(nrec >= 0 and nrec <= 0x7fffffff, "bad argument #2 to 'create' (out of range)")
	_assert(nrec <= 1 << 30, "table overflow")
	return {}
end
function table.insert(list, ...)
	local n = _select('#', ...)
	if n == 1 then
		list[#list+1] = ...
	elseif n == 2 then
		local pos, value = ...
		for i = #list,pos,-1 do
			list[i+1] = list[i]
		end
		list[pos] = value
	else
		_error("wrong number of arguments to 'insert'")
	end
end
function table.remove(list, pos)
	local ret
	if pos then
		ret = list[pos]
		for i = pos,#list-1 do
			list[i] = list[i+1]
		end
	else
		ret = list[#list]
	end
	list[#list] = nil
	return ret
end
function table.move(a1, f, e, t, a2)
	a2 = a2 or a1
	if e >= f then
		if t > e or t <= f or a1 ~= a2 then
			for i = 0, e - f do
				a2[t + i] = a1[f + i]
			end
		else
			for i = e - f, 0, -1 do
				a2[t + i] = a1[f + i]
			end
		end
	end
	return a2
end

-- TODO use a better sort; this fails on a big list of 0s
local function partitioncmp(list, comp, lo, hi)
	local pivot, i = list[hi], lo
	for j = lo, hi-1 do
		local t = list[j]
		if comp(t, pivot) then
			list[j] = list[i]
			list[i] = t
			i = i + 1
		end
	end
	list[hi] = list[i]
	list[i] = pivot
	return i
end
local function qsortcmp(list, comp, lo, hi)
	if lo < hi then
		local p = partitioncmp(list, comp, lo, hi)
		qsortcmp(list, comp, lo, p - 1)
		return qsortcmp(list, comp, p + 1, hi)
	end
end
local function partition(list, lo, hi)
	local pivot, i = list[hi], lo
	for j = lo, hi-1 do
		local t = list[j]
		if t < pivot then
			list[j] = list[i]
			list[i] = t
			i = i + 1
		end
	end
	list[hi] = list[i]
	list[i] = pivot
	return i
end
local function qsort(list, lo, hi)
	if lo < hi then
		local p = partition(list, lo, hi)
		qsort(list, lo, p - 1)
		return qsort(list, p + 1, hi)
	end
end
function table.sort(list, comp)
	if comp then
		return qsortcmp(list, comp, 1, #list)
	else
		return qsort(list, 1, #list)
	end
end

-- Files are tables with iometa as metatable, the host's file number at key FD.
-- TODO a userdata type, type(io.stdout) is 'table' for now
local iometa = {}
local FD = {}
local function mkfile(fd, popen)
	return debug_setmetatable({ [FD] = fd, popen = popen }, iometa)
end
local function io_type(f)
	if debug_getmetatable(f) == iometa then
		return f[FD] and 'file' or 'closed file'
	end
end
io.type = io_type
local function checkfile(f, fname)
	local fd = debug_getmetatable(f) == iometa and f[FD]
	if not fd then
		_error("bad argument #1 to '" .. fname .. "' (" ..
			(debug_getmetatable(f) == iometa and 'attempt to use a closed file' or 'FILE* expected') .. ")")
	end
	return fd
end
local function io_open(filename, mode)
	_assert(_type(filename) == 'string', "bad argument #1 to 'open' (string expected)")
	mode = mode or 'r'
	local fd = host('open', filename, mode)
	if math_type(fd) == 'integer' then
		return mkfile(fd)
	end
	return nil, fd, 2
end
io.open = io_open
function io.popen(cmd, mode)
	_assert(mode == nil or mode == 'r', "io.popen: only mode 'r' is supported")
	local fd = host('popen', cmd)
	if math_type(fd) == 'integer' then
		return mkfile(fd, true)
	end
	return nil, fd
end
local stdin, stdout, stderr = mkfile(0), mkfile(1), mkfile(2)
io.stdin, io.stdout, io.stderr = stdin, stdout, stderr
local io_in, io_out = stdin, stdout

local function readfmts(fd, ...)
	local n = _select('#', ...)
	if n == 0 then
		return host('read', fd, 'l')
	end
	local res = {}
	for i = 1, n do
		local fmt = _select(i, ...)
		if _type(fmt) == 'string' then
			if string_byte(fmt, 1) == 42 then -- old style '*a'
				fmt = string_sub(fmt, 2)
			end
			fmt = string_sub(fmt, 1, 1)
			_assert(fmt == 'a' or fmt == 'l' or fmt == 'L', "bad argument #" .. i .. " to 'read' (invalid format)")
		else
			fmt = tointeger(fmt)
			_assert(fmt, "bad argument #" .. i .. " to 'read' (invalid format)")
		end
		local v = host('read', fd, fmt)
		res[i] = v
		if v == nil then
			return table_unpack(res, 1, i)
		end
	end
	return table_unpack(res, 1, n)
end
local function writeargs(f, fd, ...)
	for i = 1, _select('#', ...) do
		local s = _select(i, ...)
		if _type(s) == 'number' then
			s = s .. ''
		end
		_assert(_type(s) == 'string', "bad argument #" .. i .. " to 'write' (string expected, got " .. _type(s) .. ")")
		host('write', fd, s)
	end
	return f
end
local function fileclose(f)
	local fd = checkfile(f, 'close')
	host('close', fd)
	f[FD] = nil
	if f.popen then
		return true, 'exit', 0
	end
	return true
end
local function filelines(f, fd, close, ...)
	local n = _select('#', ...)
	local fmts = { ... }
	return function()
		local fd = checkfile(f, 'lines')
		local v
		if n == 0 then
			v = host('read', fd, 'l')
		else
			v = readfmts(fd, table_unpack(fmts, 1, n))
		end
		if v == nil and close then
			fileclose(f)
		end
		return v
	end
end

iometa.__index = iometa
iometa.__name = 'FILE*'
function iometa:read(...)
	return readfmts(checkfile(self, 'read'), ...)
end
function iometa:write(...)
	return writeargs(self, checkfile(self, 'write'), ...)
end
function iometa:lines(...)
	return filelines(self, checkfile(self, 'lines'), false, ...)
end
iometa.close = fileclose
function iometa:flush()
	checkfile(self, 'flush')
	return self
end
function iometa:setvbuf()
	checkfile(self, 'setvbuf')
	return true
end
function iometa:seek()
	checkfile(self, 'seek')
	return nil, 'seek is not supported'
end
function iometa:__tostring()
	if self[FD] then
		return 'file (' .. hexid(self) .. ')'
	end
	return 'file (closed)'
end

function io.input(file)
	if _type(file) == 'string' then
		io_in = _assert(io_open(file))
	elseif file ~= nil then
		checkfile(file, 'input')
		io_in = file
	end
	return io_in
end
function io.output(file)
	if _type(file) == 'string' then
		io_out = _assert(io_open(file, 'w'))
	elseif file ~= nil then
		checkfile(file, 'output')
		io_out = file
	end
	return io_out
end
function io.read(...)
	return readfmts(checkfile(io_in, 'read'), ...)
end
function io.write(...)
	return writeargs(io_out, checkfile(io_out, 'write'), ...)
end
function io.flush()
	return io_out
end
function io.lines(fname, ...)
	if fname == nil then
		return filelines(io_in, checkfile(io_in, 'lines'), false, ...)
	end
	local f, err = io_open(fname)
	if not f then
		_error(err)
	end
	return filelines(f, f[FD], true, ...)
end
function io.close(file)
	return fileclose(file or io_out)
end

function os.getenv(name)
	return host('getenv', name)
end
function os.clock()
	return host('clock')
end
function os.time(t)
	_assert(t == nil, 'os.time: a table argument is not supported')
	return host('time')
end
function os.exit(code)
	if code == nil or code == true then
		code = 0
	elseif code == false then
		code = 1
	end
	host('exit', code)
end
function os.remove(name)
	local r = host('remove', name)
	if r == true then
		return true
	end
	return nil, r
end

function os.difftime(t2, t1)
	return t2 - t1
end
function os.setlocal(locale)
	if not locale or locale == '' or locale == 'C' then
		return 'C'
	else
		return nil
	end
end

function coro_wrap_handler(t, ...)
	if t then
		return ...
	else
		return _error(...)
	end
end
function coroutine.wrap(f)
	local c = co_create(f)
	return function(...)
		return coro_wrap_handler(co_resume(c, ...))
	end
end
-- the wasm status traps on a non coroutine, so check here
local co_status = coroutine.status
function coroutine.status(co)
	if _type(co) ~= 'thread' then
		_error("bad argument #1 to 'status' (coroutine expected)")
	end
	return co_status(co)
end
-- prelude runs on the main coroutine, so this is it
local co_main = co_running()
function coroutine.isyieldable(co)
	if co == nil then
		local a, ismain = co_running()
		return not ismain
	end
	return co ~= co_main
end

function print(...)
	local n = _select('#', ...)
	local t = {}
	for i = 1, n do
		t[i] = _tostring((_select(i, ...)))
	end
	host('write', 1, table.concat(t, '\t', 1, n) .. '\n')
end

-- The wasm engine owns the GC, so this only answers like Lua would
local gcopts = { collect = 0, stop = 0, restart = 0, count = 0.0, step = true, isrunning = true }
local gcmode = 'incremental'
local gcparams = { minormul = 20, majorminor = 50, minormajor = 70, pause = 200, stepmul = 200, stepsize = 13 }
function collectgarbage(opt, name, value)
	opt = opt or 'collect'
	-- changing mode gives the mode before
	if opt == 'incremental' or opt == 'generational' then
		local prev = gcmode
		gcmode = opt
		return prev
	end
	-- param gives the value before, & sets it when value is given
	if opt == 'param' then
		local prev = gcparams[name]
		if prev == nil then
			_error("bad argument #2 to 'collectgarbage' (invalid option '" .. _tostring(name) .. "')")
		end
		if value ~= nil then
			gcparams[name] = value
		end
		return prev
	end
	local r = gcopts[opt]
	if r == nil then
		_error("bad argument #1 to 'collectgarbage' (invalid option '" .. _tostring(opt) .. "')")
	end
	return r
end

function pairs(t)
	local mt = _getmetatable(t)
	if mt then
		local __pairs = mt.__pairs
		if __pairs then
			local a, b, c = __pairs(t)
			return a, b, c
		end
	end
	return _next, t, nil
end
local _pairs = pairs

-- ipairs' iterator: key then value, stops at the first nil
local function inext(a, b)
	b = b + 1
	local v = a[b]
	if v ~= nil then
		return b, v
	end
end
function ipairs(t)
	local mt = _getmetatable(t)
	if mt then
		local __ipairs = _rawget(mt, '__ipairs')
		if __ipairs then
			local a, b, c = __ipairs(t)
			return a, b, c
		end
	end
	return inext, t, 0
end

-- Error positions, runtime error messages & the debug library, from the call frames
-- (_luwa.frame) & the info table load gives each function (_luwa.fn_info).
-- Functions without info are builtins (info false) or prelude Lua (nil). Prelude functions stand in
-- for C functions, so errors they raise get the position of the Lua code calling them
local rawerror = _error
local _frame, fn_info = _luwa.frame, _luwa.fn_info
local string_find, string_match = string.find, string.match
local CALLTY = 3 -- calltypes.call in frame.lua: the frame under it hasn't started yet

-- co's frames from the top, as { fn, pc, ty, pend }. Frames of outer calls in a call chain
-- that haven't started are left out, pend counts them under each frame
local function stackof(co)
	local list, n, above = {}, 0, nil
	while true do
		local fn, pc, ty = _frame(co, n)
		if not pc then
			break
		end
		if above == CALLTY then
			local last = list[#list]
			last.pend = last.pend + 1
		elseif fn == rawerror then
			-- error is the prelude function & this builtin, count them as 1 like C Lua's error
		else
			list[#list+1] = { fn = fn, pc = pc, ty = ty, pend = 0 }
		end
		above = ty
		n = n + 1
	end
	return list
end
-- The running coro's frames. list[off] is the function calling levels, list[off+1] its caller...
-- Above it are _frame, stackof & levels
local function levels()
	return stackof(nil), 4
end
-- Frames of co & where level 0 is, for debug functions taking an optional thread
local function threadlevels(co)
	if co == nil or co == co_running() then
		local list = stackof(nil)
		-- _frame, stackof, threadlevels, then the debug function calling this
		return list, 4
	end
	return stackof(co), 1
end

-- Line of the op before pc, -1 if unknown. A frame's pc is just after its current op
local function currentline(info, pc)
	local li = info.lines
	local n = li and #li >> 1 or 0
	if n == 0 then
		return -1
	end
	local lo, hi, best = 1, n, 1
	while lo <= hi do
		local mid = (lo + hi) >> 1
		if li[2*mid-1] <= pc - 1 then
			best = mid
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	return li[2*best]
end

-- "src:line: " for list[i], or '' for builtins. Prelude frames pass it on to their caller
local function where(list, i)
	while list[i] do
		local info = fn_info(list[i].fn)
		if info then
			local line = currentline(info, list[i].pc)
			return line > 0 and info.short_src .. ':' .. line .. ': ' or ''
		elseif info == false or list[i].fn == nil then
			return ''
		end
		i = i + 1
	end
	return ''
end

-- What list[i] was called as, from its caller's call site: name, namewhat
local function callname(list, i)
	local caller = list[i+1]
	local info = caller and fn_info(caller.fn)
	local names = info and info.names[caller.pc]
	local d = names and names.call and names[1 + list[i].pend]
	if d then
		local what, name = string_match(d, "^(.-) '(.*)'$")
		return name, what
	end
	return nil, ''
end

function error(msg, level)
	level = level or 1
	if _type(msg) == 'string' and _type(level) == 'number' and level > 0 then
		local list, off = levels()
		msg = where(list, off + level) .. msg
	end
	return rawerror(msg)
end
_error = error

-- Called by the Error mop: kind of operation & its operands. Raises the error like C Lua words it.
-- The op's operand names are in its function's info.names at the op's pc
local function rterror(kind, a, b)
	local list, off = levels()
	local fr = list[off+1]
	local info = fr and fn_info(fr.fn)
	local names = info and info.names[fr.pc]
	local function nm(k)
		local d = names and names[k]
		return d and ' (' .. d .. ')' or ''
	end
	local msg
	if kind == 'index' then
		msg = 'attempt to index a ' .. _type(a) .. ' value' .. nm(1)
	elseif kind == 'arith' or kind == 'bitwise' then
		-- blame the first operand unless it's a number
		local k, v = 1, a
		if math_type(a) then
			k, v = 2, b
		end
		msg = 'attempt to perform ' .. (kind == 'arith' and 'arithmetic' or 'bitwise operation') ..
			' on a ' .. _type(v) .. ' value' .. nm(k)
	elseif kind == 'concat' then
		local k, v = 1, a
		if _type(a) == 'string' or _type(a) == 'number' then
			k, v = 2, b
		end
		msg = 'attempt to concatenate a ' .. _type(v) .. ' value' .. nm(k)
	elseif kind == 'compare' then
		local ta, tb = _type(a), _type(b)
		msg = ta == tb and 'attempt to compare two ' .. ta .. ' values' or 'attempt to compare ' .. ta .. ' with ' .. tb
	elseif kind == 'len' then
		msg = 'attempt to get length of a ' .. _type(a) .. ' value' .. nm(1)
	elseif kind == 'defined' then
		msg = "global '" .. a .. "' already defined"
	else
		msg = 'invalid operation'
	end
	return error(msg, 2)
end
-- Called in place of a value that can't be called, with the value & the args
local function callerror(v)
	local list, off = levels()
	local name, what = callname(list, off)
	return error('attempt to call a ' .. _type(v) .. ' value' .. (name and ' (' .. what .. " '" .. name .. "')" or ''), 2)
end
_luwa.seterrfns(rterror, callerror)

-- Name of a global function, like C Lua's tracebacks find: 'print', 'string.rep'
local function globalname(fn)
	if fn == nil then
		return nil
	end
	for mod, t in _next, package.loaded do
		if _type(t) == 'table' then
			for k, v in _next, t do
				if v == fn and _type(k) == 'string' then
					return mod == '_G' and k or mod .. '.' .. k
				end
			end
		end
	end
end

-- How a traceback names list[i], like 5.5: call site name, main chunk, global name, then where it's defined
local function funcdesc(list, i, info)
	local name, what = callname(list, i)
	if name then
		return what .. " '" .. name .. "'"
	elseif info and info.what == 'main' then
		return 'main chunk'
	end
	local g = globalname(list[i].fn)
	if g then
		return "function '" .. g .. "'"
	elseif info then
		return 'function <' .. info.short_src .. ':' .. info.linedefined .. '>'
	end
	return '?'
end

function debug.traceback(co, msg, level)
	if _type(co) ~= 'thread' then
		co, msg, level = nil, co, msg
	end
	if msg ~= nil and _type(msg) ~= 'string' and _type(msg) ~= 'number' then
		return msg
	end
	local list, off = threadlevels(co)
	if off > 1 then
		level = level or 1
	else
		level = level or 0
	end
	-- lines, a run of frames without info (builtins & prelude) makes 1 [C] line
	local lines = {}
	local i = off + level
	while list[i] do
		local fr = list[i]
		local info = fn_info(fr.fn)
		if info then
			local cl = currentline(info, fr.pc)
			lines[#lines+1] = info.short_src .. ':' .. (cl > 0 and cl .. ':' or '') .. ' in ' .. funcdesc(list, i, info)
			i = i + 1
		elseif fr.fn == nil then
			i = i + 1
		else
			-- name the run by how its bottom frame was called, else its first global function from the bottom.
			-- Runtime error helpers are hidden
			local j, hide, desc = i, false, nil
			while list[j] and list[j].fn ~= nil and not fn_info(list[j].fn) do
				if list[j].fn == rterror or list[j].fn == callerror then
					hide = true
				end
				j = j + 1
			end
			local name, what = callname(list, j - 1)
			if name then
				desc = what .. " '" .. name .. "'"
			end
			for k = j - 1, i, -1 do
				local g = not desc and globalname(list[k].fn)
				if g then
					desc = "function '" .. g .. "'"
					break
				end
			end
			if not hide then
				lines[#lines+1] = '[C]: in ' .. (desc or '?')
			end
			i = j
		end
	end
	-- like C Lua, long tracebacks keep the first 10 & last 11 levels
	local out = { msg ~= nil and msg .. '\nstack traceback:' or 'stack traceback:' }
	for k = 1, #lines do
		if #lines > 22 and k == 11 then
			out[#out+1] = '\n\t...\t(skipping ' .. (#lines - 21) .. ' levels)'
		end
		if #lines <= 22 or k <= 10 or k > #lines - 11 then
			out[#out+1] = '\n\t' .. lines[k]
		end
	end
	return table.concat(out)
end

function debug.getinfo(co, f, what)
	if _type(co) ~= 'thread' then
		co, f, what = nil, co, f
	end
	local argn = co and 2 or 1
	what = what or 'flnSrtu'
	if _type(what) ~= 'string' or string_find(what, '[^SlnrutfL]') then
		_error("bad argument #" .. (argn + 1) .. " to 'getinfo' (invalid option)")
	end
	local fn, list, i
	if _type(f) == 'function' then
		fn = f
	elseif math_type(f) == 'integer' or (_type(f) == 'number' and tointeger(f)) then
		local off
		list, off = threadlevels(co)
		i = off + tointeger(f)
		if f < 0 or not list[i] then
			return nil
		end
		fn = list[i].fn
	else
		_error("bad argument #" .. argn .. " to 'getinfo' (function or level expected)")
	end
	local info = fn_info(fn)
	local t = {}
	if string_find(what, 'S', 1, true) then
		if info then
			t.source, t.short_src, t.what = info.source, info.short_src, info.what
			t.linedefined, t.lastlinedefined = info.linedefined, info.lastlinedefined
		else
			t.source, t.short_src, t.what = '=[C]', '[C]', 'C'
			t.linedefined, t.lastlinedefined = -1, -1
		end
	end
	if string_find(what, 'l', 1, true) then
		t.currentline = list and info and currentline(info, list[i].pc) or -1
	end
	if string_find(what, 'u', 1, true) then
		t.nups = info and info.nups or 0
		t.nparams = info and info.nparams or 0
		t.isvararg = not info or info.isvararg
	end
	if string_find(what, 'n', 1, true) then
		if list then
			t.name, t.namewhat = callname(list, i)
		else
			t.namewhat = ''
		end
	end
	if string_find(what, 'r', 1, true) then
		t.ftransfer, t.ntransfer = 0, 0
	end
	if string_find(what, 't', 1, true) then
		t.istailcall = false
	end
	if string_find(what, 'f', 1, true) then
		t.func = fn
	end
	if string_find(what, 'L', 1, true) and info then
		local al, li = {}, info.lines
		for k = 2, #li, 2 do
			al[li[k]] = true
		end
		t.activelines = al
	end
	return t
end

-- Source name to show in messages, like C Lua's luaO_chunkid
local function chunkid(src)
	local c = string_byte(src)
	if c == 61 then -- =name
		return string_sub(src, 2, 60)
	elseif c == 64 then -- @file
		return #src <= 60 and string_sub(src, 2) or '...' .. string_sub(src, -56)
	end
	local nl = string_find(src, '\n', 1, true)
	if not nl and #src < 45 then
		return '[string "' .. src .. '"]'
	end
	local l = string_sub(src, 1, nl and nl - 1 or #src)
	if #l > 45 then
		l = string_sub(l, 1, 45)
	end
	return '[string "' .. l .. '..."]'
end

local fakereqtbl = {
	ast = _luwa.ast,
	bc = _luwa.bc,
	lex =  _luwa.lex,
	astgen = _luwa.astgen,
	bcgen = _luwa.bcgen,
}
local fakereqcache = {}
local fakereqenv
local function fakereq(s)
	local fs = fakereqcache[s]
	if not fs then
		fs = fakereqtbl[s](fakereqenv)
		fakereqcache[s] = fs
	end
	return fs
end
-- In a function with a named vararg table t, ... reads t[1..t.n]. bcgen emits calls to this
local function vargunpack(t)
	local n = _rawget(t, 'n')
	if math_type(n) ~= 'integer' or n < 0 or n > 0x3fffffff then
		error("vararg table has no proper 'n'", 2)
	end
	return table_unpack(t, 1, n)
end
fakereqenv = {
	_vargunpack = vargunpack,
	assert = _assert,
	-- compile errors carry their own position
	error = rawerror,
	tostring = _tostring,
	getmetatable = _getmetatable,
	ipairs = ipairs,
	pairs = _pairs,
	pcall = _pcall,
	require = fakereq,
	select = _select,
	setmetatable = setmetatable,
	type = type,
	coroutine = {
		wrap = coroutine.wrap,
		yield = coroutine.yield,
	},
	math = {
		type = math_type,
		max = math.max,
	},
	string = {
		byte = string.byte,
		match = string.match,
		pack = string.pack,
		unpack = string.unpack,
	},
	table = {
		insert = table.insert,
		remove = table.remove,
		sort = table.sort,
		unpack = table_unpack,
	},
}
local astgen = fakereq('astgen')
local bcgen = fakereq('bcgen')

-- Make a function object from bcgen's output.
-- Nested functions are bcgen tables in consts, turn those into function objects too.
-- LoadFunc copies these and fills in frees
-- src & short are the chunk's source name & how messages show it
local function asm2fn(asm, src, short, main)
	local fn = _luwa.fn_new()
	_luwa.fn_set_info(fn, {
		source = src,
		short_src = short,
		what = main and 'main' or 'Lua',
		linedefined = main and 0 or asm.linedefined or -1,
		lastlinedefined = main and 0 or asm.lastlinedefined or -1,
		-- pc, line pairs & pc -> operand names, from bcgen
		lines = asm.lineinfo,
		names = asm.opnames,
		name = asm.fname,
		-- the main chunk's _ENV param is an upvalue in C Lua
		nparams = main and 0 or #asm.params,
		isvararg = asm.isdotdotdot,
		nups = main and 1 or #asm.freenames,
		upnames = main and { '_ENV' } or asm.freenames,
	})
	_luwa.fn_set_localc(fn, #asm.locals)
	_luwa.fn_set_paramc(fn, #asm.params)
	_luwa.fn_set_isdotdotdot(fn, asm.isdotdotdot)
	_luwa.fn_set_bc(fn, string_char(table_unpack(asm.bc)))
	local consts = {}
	for i=1, #asm.consts do
		local c = asm.consts[i]
		if type(c) == 'table' then
			c = asm2fn(c, src, short)
		end
		consts[i] = c
	end
	_luwa.fn_set_consts(fn, _luwa.vec_new(table_unpack(consts)))
	return fn
end

local function _load(src, name, mode, env)
	if name == nil then
		name = _type(src) == 'string' and src or '=(load)'
	end
	if _type(src) == 'function' then
		-- a function giving pieces until nil or ''
		local parts = {}
		while true do
			local piece = src()
			if piece == nil or piece == '' then
				break
			end
			parts[#parts + 1] = piece
		end
		src = table.concat(parts)
	end
	local short = chunkid(name)
	local lx, vals, lines = _luwa.lexgen(src)
	if not lx then
		return nil, vals
	end
	local ok, root = _pcall(astgen, lx, vals, lines, short)
	if not ok then
		return nil, root
	end
	local ok, asm = _pcall(bcgen, root, short)
	if not ok then
		return nil, asm
	end
	local fn = asm2fn(asm, name, short, true)
	_luwa.fn_set_frees(fn, _luwa.vec_new(env or _ENV))
	-- compiled chunks take _ENV as their first param, like the prelude does
	-- TODO make _ENV the chunk's first free instead, saving this extra call
	env = env or _ENV
	return function(...)
		return fn(env, ...)
	end
end
loadstring = _load
load = _load
local function _loadfile(fname, mode, env)
	local file, err
	if fname == nil then
		file = io_in
	else
		file, err = io_open(fname)
		if not file then
			return nil, 'cannot open ' .. err
		end
	end
	local src = file:read('a')
	if fname ~= nil then
		file:close()
	end
	-- skip a first line starting with #, like a #! line. As a comment, so line numbers stay the same
	if string_byte(src, 1) == 35 then
		src = '--' .. src
	end
	return _load(src, fname and '@' .. fname or '=stdin', mode, env)
end
loadfile = _loadfile
function dofile(fname)
	local f = _assert(_loadfile(fname))
	return f()
end

package.path = os.getenv('LUA_PATH') or './?.lua;./?/init.lua'
package.cpath = ''
local loaded = package.loaded
local preload = {}
package.preload = preload
-- First file name from path's templates that can be opened, with . in name as /
function package.searchpath(name, path, sep, rep)
	sep = sep or '.'
	rep = rep or '/'
	if sep ~= '' then
		name = string.gsub(name, string.gsub(sep, '%p', '%%%0'), (string.gsub(rep, '%%', '%%%%')))
	end
	local tried = {}
	for tmpl in string.gmatch(path, '[^;]+') do
		local fname = string.gsub(tmpl, '%?', (string.gsub(name, '%%', '%%%%')))
		local f = io_open(fname)
		if f then
			f:close()
			return fname
		end
		tried[#tried + 1] = "\n\tno file '" .. fname .. "'"
	end
	return nil, table.concat(tried)
end
local searchers = {
	function(name)
		local pre = preload[name]
		if pre then
			return pre, ':preload:'
		end
		return "\n\tno field package.preload['" .. name .. "']"
	end,
	function(name)
		local fname, err = package.searchpath(name, package.path)
		if fname then
			local f, err = _loadfile(fname)
			if not f then
				_error("error loading module '" .. name .. "' from file '" .. fname .. "':\n\t" .. err)
			end
			return f, fname
		else
			return err
		end
	end
}
package.searchers = searchers
local function _require(modname)
	_assert(_type(modname) == 'string' or _type(modname) == 'number', "bad argument #1 to 'require' (string expected)")
	modname = modname .. ''
	local lded = loaded[modname]
	if lded ~= nil then
		return lded
	end
	local msg = {}
	for i = 1, #searchers do
		local f, p = searchers[i](modname)
		if _type(f) == 'function' then
			local ret = f(modname, p)
			if ret ~= nil then
				loaded[modname] = ret
			elseif loaded[modname] == nil then
				loaded[modname] = true
			end
			return loaded[modname], p
		elseif _type(f) == 'string' then
			msg[#msg + 1] = f
		end
	end
	return _error("module '" .. modname .. "' not found:" .. table.concat(msg))
end
require = _require

-- An integer id where Lua gives a light userdata. Same id means same variable
local upvalid = _luwa.upvalid
function debug.upvalueid(f, n)
	if _type(f) ~= 'function' then
		_error("bad argument #1 to 'upvalueid' (function expected, got " .. _type(f) .. ")")
	end
	local i = tointeger(n)
	if not i then
		_error("bad argument #2 to 'upvalueid' (number expected, got " .. _type(n) .. ")")
	end
	if i < 1 or i > 0x7fffffff then
		return nil
	end
	return upvalid(f, i)
end

local registry = {}
function debug.getregistry()
	return registry
end

function debug.debug()
	while true do
		stdout:write('lua_debug> ')
		local line = stdin:read('l')
		if line == nil or line == 'cont' then
			return
		end
		local f, err = _load(line)
		if f then
			local ok, msg = _pcall(f)
			if not ok then
				stdout:write(_tostring(msg), '\n')
			end
		else
			stdout:write(_tostring(err), '\n')
		end
	end
end
